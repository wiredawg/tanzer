package provide tanzer::session 0.0.1
package require tanzer::response
package require tanzer::error
package require TclOO

::oo::class create ::tanzer::session

::oo::define ::tanzer::session constructor {_server _sock _proto} {
    my variable server sock proto request readBytes \
        route handler state responded config

    set module [format "::tanzer::%s::request" $_proto]

    set server    $_server
    set sock      $_sock
    set proto     $_proto
    set request   [$module new]
    set route     {}
    set handler   {}
    set state     [dict create]
    set responded 0

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

    set remaining [$request remaining -[string length $data]]

    if {$remaining < 0} {
        ::tanzer::error throw 400 "Request body too long"
    } elseif {$remaining > 0} {
        ::tanzer::error throw 400 "Request body too short"
    }

    #
    # Pass the current block of data to the handler.
    #
    {*}$handler read [self] $data

    #
    # If we have read the full request body, then bind the event handler to
    # the socket for writable events, and ignore readable events.
    #
    if {$remaining == 0} {
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
    my variable request

    if {[llength $args] == 0} {
        return $request
    }

    return [$request {*}$args]
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

::oo::define ::tanzer::session method send {response} {
    my variable sock responded

    if {$responded} {
        error "Already sent response"
    }

    $response write $sock

    set responded 1
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

    ::tanzer::error 404 "No suitable request handler found"
}
