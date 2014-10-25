package provide tanzer::session 0.1
package require tanzer::message::chunk
package require tanzer::response
package require tanzer::error
package require TclOO

namespace eval ::tanzer::session {
    variable timeout 5
}

::oo::class create ::tanzer::session

::oo::define ::tanzer::session constructor {newServer newSock newProto} {
    my variable server sock proto request route handler \
        cleanup state response buffer config remaining keepalive \
        active watchdog

    set server    $newServer
    set sock      $newSock
    set proto     $newProto
    set request   {}
    set route     {}
    set handler   {}
    set cleanup   {}
    set state     [dict create]
    set response  {}
    set buffer    ""
    set remaining 0
    set keepalive 1
    set active    0
    set watchdog  [after [expr {$::tanzer::session::timeout * 1000}] \
        [self] ping]

    set config(readBufferSize) [$newServer config readBufferSize]
}

::oo::define ::tanzer::session destructor {
    my variable server sock request response \
        active watchdog cleanup

    if {$request ne {}} {
        $request destroy
    }

    if {$response ne {}} {
        $response destroy
    }

    if {$sock ne {}} {
        $server forget $sock
        close $sock
        set sock {}
    }

    if {$watchdog ne {}} {
        after cancel $watchdog
    }

    my cleanup
}

::oo::define ::tanzer::session method cleanup {args} {
    my variable cleanup

    if {[llength $args] > 0} {
        set cleanup $args

        return
    }

    if {$cleanup eq {}} {
        return
    }

    set ret [{*}$cleanup]
    set cleanup {}
    return $ret
}

#
# Delegate events to a different request handler.
#
::oo::define ::tanzer::session method delegate {args} {
    my variable handler

    return [set handler $args]
}

#
# Called to allow a request handler to indicate to the session handler that the
# session is still indeed active, even if the request handler decides to side
# step the session handler for I/O event dispatch in such cases as letting the
# request handler monitor a non-server socket.
#
::oo::define ::tanzer::session method tick {} {
    my variable active

    set active 1
}

#
# Called by a watchdog timer to make sure the session is still alive, and to
# reset the timeout if it is.
#
::oo::define ::tanzer::session method ping {} {
    my variable active watchdog

    if {!$active} {
        my destroy

        return
    }

    set active 0
    set watchdog [after [expr {$::tanzer::session::timeout * 1000}] [self] ping]
}

#
# Called by request handlers to reset session state and handle keepalive
# sessions.
#
::oo::define ::tanzer::session method nextRequest {} {
    my variable server sock buffer handler route \
        request response remaining keepalive

    if {$remaining != 0} {
        ::tanzer::error throw 400 "Invalid request body length"
    }

    if {$request ne {}} {
        $request destroy
        set request {}
    }

    if {$response ne {}} {
        $response destroy
        set response {}
    }

    my cleanup

    set route   {}
    set handler {}

    fileevent $sock readable [list $server respond read $sock]
    fileevent $sock writable {}

    #
    # Determine if we need to kill the session posthaste.
    #
    if {!$keepalive || [eof $sock]} {
        my destroy

        return
    }

    #
    # If we still have data in the buffer, then we'll need to flush that out.
    #
    if {[string length $buffer] > 0} {
        my handle read
    }
}

#
# This is the first bit of code that gets executed by the server upon receipt
# of a ready event.
#
::oo::define ::tanzer::session method handle {event} {
    my variable sock server request keepalive \
        buffer config handler active

    set active   1
    set streamed 0

    if {$event eq "write"} {
        return [{*}$handler write [self]]
    }

    if {$event ne "read"} {
        error "Unknown event '$event'"
    }

    #
    # Given that this very well could be our first opportunity to read data,
    # let's make no assumptions about the state of the request and read some
    # data and pass it off to the request to see if the data is complete enough
    # to allow it to parse the headers, at least.
    #
    set data [read $sock $config(readBufferSize)]

    #
    # Create a request if one does not exist already.
    #
    if {$request eq {}} {
        set request [my request -new]
    }

    #
    # Is the request complete yet?
    #
    if {[$request incomplete]} {
        #
        # If not, buffer the data to the request and attempt to parse it.
        #
        append buffer $data

        #
        # Bail if the request is not yet parseable.
        #
        if {![$request parse buffer]} {
            return
        }

        #
        # If the request does not call for keepalive, then set the keepalive
        # count to 0.
        #
        if {![$request keepalive]} {
            set keepalive 0
        }

        #
        # We are now ready to attempt to route a handler to the
        # request.
        #
        my route

        #
        # Indicate the amount of bytes left to be read by the session handler.
        #
        set remaining [$request length]

        #
        # Flush out the existing data left over from the session buffer
        # to the handler as a read event, and subsequently trim the buffer
        # to only the parts we need.
        #
        set start 0
        set end   [expr {$remaining - 1}]
        set data  [string range $buffer $start $end]
    } else {
        append buffer $data
    }

    #
    # Pass the current block of data to the handler.
    #
    if {[$request chunked]} {
        #
        # If there is no more chunk data to decode, then we can indicate that
        # we are now ready to transition to write-ready events.
        #
        if {![::tanzer::message::chunk parse buffer {*}$handler read [self]]} {
            set streamed 1
        }
    } else {
        {*}$handler read [self] $data

        #
        # Decrement the length of the data passed to the request handler from
        # the number of bytes left for this current request.
        #
        incr remaining -[string length $data]

        #
        # If there is no more body to be read from the request body, then we
        # can transition to write-ready events.
        #
        if {$remaining == 0} {
            set streamed 1
        }
    }

    #
    # If the request is now ready, then bind the event handler to the socket
    # for writable events, and ignore readable events.
    #
    # Now, before I forget my post-rationalization, precisely, why would we
    # want to do this?  The answer is simple, my love.  This affords the
    # request handler the autonomy to decide whether or not it wants to read
    # from the socket at its own whim.  And...AND, it ought to be up to the
    # request handler to determine when it's ready to cede control back to
    # the session and spawn up a new request handler, at least in the case
    # of HTTP.
    #
    if {$streamed} {
        fileevent $sock readable {}
        fileevent $sock writable [list $server respond write $sock]
    }

    return
}

::oo::define ::tanzer::session method get {key} {
    my variable state

    return [dict get $state $key]
}

::oo::define ::tanzer::session method set {args} {
    my variable state

    foreach {name value} $args {
        dict set state $name $value
    }

    return
}

::oo::define ::tanzer::session method server {{newServer ""}} {
    my variable server

    if {$newServer ne ""} {
        set server $newServer

        return
    }

    return $server
}

::oo::define ::tanzer::session method sock {{newSock ""}} {
    my variable sock

    if {$newSock ne ""} {
        set sock $newSock

        return
    }

    return $sock
}

::oo::define ::tanzer::session method request {args} {
    my variable proto request keepalive

    array set opts {
        new 0
    }

    if {[llength $args] == 0} {
        return $request
    }

    foreach arg $args {
        switch -- $arg "-new" {
            set opts(new) 1
        } default {
            error "Invalid argument $arg"
        }
    }

    if {$opts(new)} {
        set module [format "::tanzer::%s::request" $proto]

        set request [$module new [self]]

        $request env REMOTE_ADDR [lindex [my get sockaddr] 0]
    }

    return $request
}

::oo::define ::tanzer::session method config {{name ""} {value ""}} {
    my variable config

    if {$value ne ""} {
        set config($name) $value

        return
    } elseif {$name ne ""} {
        return $config($name)
    }

    return [array get config]
}

::oo::define ::tanzer::session method state {} {
    my variable state

    return $state
}

::oo::define ::tanzer::session method read {} {
    my variable config sock 

    return [read $sock $config(readBufferSize)]
}

::oo::define ::tanzer::session method write {data} {
    my variable sock response

    set length [string length $data]

    if {[$response chunked]} {
        puts -nonewline $sock [format "%x\r\n$data\r\n" $length]
    } else {
        puts -nonewline $sock $data
    }

    return $length
}

::oo::define ::tanzer::session method send {newResponse} {
    my variable server sock response keepalive

    if {$response ne {}} {
        error "Already sent response"
    }

    $newResponse header Connection [expr {$keepalive? "Keep-Alive": "Close"}]
    $newResponse send $sock

    set response $newResponse

    $server log [self] $newResponse

    return
}

::oo::define ::tanzer::session method responded {} {
    my variable response

    return [expr {$response ne {}}]
}

::oo::define ::tanzer::session method response {} {
    my variable response

    return $response
}

::oo::define ::tanzer::session method redirect {uri} {
    set response [::tanzer::response new 301]

    $response header Location       $uri
    $response header Content-Length 0

    my send $response
}

::oo::define ::tanzer::session method ended {} {
    my variable sock request

    return [expr {[eof $sock] && [$request empty]}]
}

::oo::define ::tanzer::session method keepalive {{newValue ""}} {
    my variable keepalive

    if {$newValue ne ""} {
        set keepalive $newValue

        return
    }

    return $keepalive
}

::oo::define ::tanzer::session method route {} {
    my variable server request route handler

    if {$route ne {}} {
        return $route
    }

    #
    # Find the most appropriate route to handle the current request.
    #
    foreach candidate [$server routes] {
        if {[$request matches $candidate]} {
            set route   $candidate
            set handler [$candidate script]

            return $route
        }
    }

    ::tanzer::error throw 404 "No suitable request handler found"
}
