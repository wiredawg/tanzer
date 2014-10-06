package provide tanzer::server 0.0.1
package require tanzer::error
package require tanzer::route
package require tanzer::session
package require TclOO

::oo::class create ::tanzer::server

::oo::define ::tanzer::server constructor {args} {
    my variable routes config sessions

    set routes [list]

    array set config {
        readBufferSize 4096
        port           1337
        proto          "scgi"
    }

    if {[llength $args] == 1} {
        foreach {key value} [lindex $args 0] {
            if {[array get config $key] ne {}} {
                set config($key) $value
            }
        }
    }

    set found 0

    set test [format {
        if {$::tanzer::%s::request::proto eq "%s"} {
            set found 1
        }
    } $config(proto) $config(proto)]

    if {[catch $test error]} {
        error "Unsupported protocol $config(proto): $error"
    }

    if {!$found} {
        error "No package found for protocol $config(proto)"
    }
}

::oo::define ::tanzer::server destructor {
    my variable routes sessions

    foreach route $routes {
        $route destroy
    }

    foreach sock [array names sessions] {
        $sessions($sock) destroy
    }
}

::oo::define ::tanzer::server method config {args} {
    my variable config

    if {[llength $args] == 1} {
        return $config([lindex $args 0])
    }

    if {[llength $args] == 2} {
        return [set config([lindex $args 0]) [lindex $args 1]]
    }

    error "Invalid command invocation"
}

::oo::define ::tanzer::server method route {method pattern args} {
    my variable routes

    lappend routes [::tanzer::route new $method $pattern $args]
}

::oo::define ::tanzer::server method routes {} {
    my variable routes

    return $routes
}

::oo::define ::tanzer::server method forget {sock} {
    my variable sessions

    if {[array get sessions $sock] eq {}} {
        return
    }

    unset sessions($sock)
}

::oo::define ::tanzer::server method close {sock} {
    my variable sessions

    if {[array get sessions $sock] eq {}} {
        return
    }

    $sessions($sock) destroy

    my forget $sock
}

::oo::define ::tanzer::server method respond {event sock} {
    my variable sessions

    set session $sessions($sock)

    if {[$session ended]} {
        my close $sock

        return
    }

    ::tanzer::error try {
        $session handle $event
    } catch e {
        if {[::tanzer::error servable $e]} {
            #
            # If the error we have received is servable and thus a structured
            # error, then we can immediately generate a response page and consider
            # it an error meant to be sent to the client.
            #
            set response [::tanzer::error response $e]
        } else {
            #
            # Otherwise, generate a generic 500 Internal Server Error response,
            # and log that in the error log, if available.
            #
            set response [::tanzer::error response \
                [::tanzer::error new 500 $e]]
        }

        $session send $response
        $response destroy

        my close $sock
    }
}

::oo::define ::tanzer::server method accept {sock addr port} {
    my variable config sessions

    fconfigure $sock \
        -translation binary \
        -blocking    0 \
        -buffering   full \
        -buffersize  $config(readBufferSize)

    set session [::tanzer::session create \
        ::tanzer::session-$sock [self] $sock $config(proto)]

    $session set sockaddr [list $addr $port]

    fileevent $sock readable [list [self] respond read $sock]

    set sessions($sock) $session

    return
}

::oo::define ::tanzer::server method listen {} {
    my variable config

    socket -server [list [self] accept] $config(port)
}
