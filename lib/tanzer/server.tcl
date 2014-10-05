package provide tanzer::server 0.0.1
package require tanzer::route
package require tanzer::session
package require TclOO

::oo::class create ::tanzer::server

::oo::define ::tanzer::server constructor {args} {
    my variable routes config sessions

    if {[llength $args] > 0} {
        set routes [lindex $routes 0]
    }

    array set config {
        readBufferSize 4096
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

    if {[catch {$session handle $event} error]} {
        puts "Error: $error\n$::errorInfo"

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

    set session [::tanzer::session create ::tanzer::session-$sock [self] $sock]

    $session set sockaddr [list $addr $port]

    fileevent $sock readable [list [self] respond read $sock]

    set sessions($sock) $session

    return
}

::oo::define ::tanzer::server method listen {port} {
    socket -server [list [self] accept] $port
}
