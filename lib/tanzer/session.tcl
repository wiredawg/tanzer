package provide tanzer::session 0.0.1
package require tanzer::response
package require tanzer::error
package require TclOO

::oo::class create ::tanzer::session

::oo::define ::tanzer::session constructor {_server _sock _proto} {
    my variable server sock proto request readBytes \
        route handler state response config

    set server    $_server
    set sock      $_sock
    set proto     $_proto
    set request   {}
    set route     {}
    set handler   {}
    set state     [dict create]
    set response  {}
    set keepalive 5

    set config(readBufferSize) [$_server config readBufferSize]
}

::oo::define ::tanzer::session destructor {
    my variable server sock request

    $request destroy

    if {$sock ne {}} {
        $server forget $sock
        close $sock
        set sock {}
    }
}

#
# Delegate events to a different request handler.
#
::oo::define ::tanzer::session method delegate {args} {
    my variable handler

    return [set handler $args]
}

#
# This is the first bit of code that gets executed by the server upon receipt
# of a ready event.
#
::oo::define ::tanzer::session method handle {event} {
    my variable sock server request \
        config handler

    if {$event eq "write"} {
        return [{*}$handler write [self] ""]
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
        $request buffer $data

        #
        # Bail if the request is not yet parseable.
        #
        if {![$request parse]} {
            return
        }

        #
        # We are now ready to attempt to route a handler to the
        # request.
        #
        my route

        #
        # Flush out the existing data left over from the request buffer
        # to the handler as a read event.
        #
        set data [$request data]
    }

    #
    # Pass the current block of data to the handler.
    #
    {*}$handler read [self] $data

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
    if {[$request ready]} {
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

::oo::define ::tanzer::session method server {args} {
    my variable server

    if {[llength $args] == 0} {
        return $server
    }

    return [$server {*}$args]
}

::oo::define ::tanzer::session method sock {args} {
    my variable sock

    if {[llength $args] == 0} {
        return $sock
    }

    return [chan {*}$args $sock]
}

::oo::define ::tanzer::session method request {args} {
    my variable proto request

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

        return [set request [$module new [self]]]
    }

    return $request
}

::oo::define ::tanzer::session method config {args} {
    my variable config

    if {[llength $args] == 0} {
        return [array get config]
    }

    if {[llength $args] == 1} {
        return $config([lindex $args 0])
    }

    if {[llength $args] == 2} {
        return [set config([lindex $args 0]) [lindex $args 1]]
    }

    error "Invalid command invocation"
}

::oo::define ::tanzer::session method state {} {
    my variable state

    return $state
}

::oo::define ::tanzer::session method write {data} {
    my variable sock

    return [puts -nonewline $sock $data]
}

::oo::define ::tanzer::session method send {_response} {
    my variable server sock response

    if {$response ne {}} {
        error "Already sent response"
    }

    $_response write $sock

    [$server logger] log $server [self] $_response

    set response $_response
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

    $response destroy
}

::oo::define ::tanzer::session method ended {} {
    my variable sock request

    return [expr {[eof $sock] && [$request empty]}]
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
