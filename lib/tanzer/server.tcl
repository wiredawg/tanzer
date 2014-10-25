package provide tanzer::server 0.1
package require tanzer::error
package require tanzer::route
package require tanzer::logger
package require tanzer::session
package require TclOO

## @file tanzer/server.tcl
# The connection acceptance server
#
namespace eval ::tanzer::server {
    variable name    "tanzer"
    variable version "0.1"
}

##
# `::tanzer::server` manages the listener socket and creates new sessions for
# each connecting client.
#
::oo::class create ::tanzer::server

##
# Create a new server, with optional `$newOpts` list of pairs indicating
# configuration.  Accepted values are:
#
# - `readBufferSize`
#
#   Defaults to 4096.  The size of buffer used to read from remote sockets and
#   local files.
#
# - `port`
#
#   The TCP port number to open a listening socket for.
#
# - `proto`
#
#   The protocol to accept connections for.  Defaults to `http`, but can be
#   `scgi`.
# .
#
::oo::define ::tanzer::server constructor {{newOpts {}}} {
    my variable routes config sessions logger

    set opts   {}
    set routes [list]
    set logger ::tanzer::logger::default

    array set config {
        readBufferSize 4096
        port           8080
        proto          "http"
    }

    if {$newOpts ne {}} {
        set opts [dict create {*}$newOpts]
    }

    foreach {key value} $opts {
        if {[array get config $key] ne {}} {
            set config($key) $value
        }
    }

    #
    # If need be, instantiate a logger object, passing configuration directives
    # directly from the caller here as required.
    #
    if {[dict exists $opts logging]} {
        set logger [::tanzer::logger new \
            [set config(logging) [dict get $opts logging]]]
    }

    #
    # Determine if support for the protocol specified at object instantiation
    # time is present.
    #
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

##
# Query configuration value `$name` from server, or set configuration for
# `$name` with `$value`.
#
::oo::define ::tanzer::server method config {name {value ""}} {
    my variable config

    if {$value ne ""} {
        set config($name) $value

        return
    }

    return $config($name)
}

::oo::define ::tanzer::server method log {args} {
    my variable logger

    return [$logger log [self] {*}$args]
}

::oo::define ::tanzer::server method route {method pattern host args} {
    my variable routes

    lappend routes [::tanzer::route new $method $pattern $host $args]
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

    close $sock

    $sessions($sock) destroy

    my forget $sock
}

::oo::define ::tanzer::server method respond {event sock} {
    my variable sessions logger

    set session $sessions($sock)

    if {[$session ended]} {
        my close $sock

        return
    }

    ::tanzer::error try {
        $session handle $event
    } catch e {
        #
        # If the session has already sent a response for the current request,
        # then simply log the error and move on.
        #
        if {[$session responded]} {
            $logger err [self] $e

            my close $sock

            return
        }

        if {[::tanzer::error servable $e]} {
            if {[::tanzer::error status $e] >= 500} {
                $logger err [self] $e
            }

            set response [::tanzer::error response $e]
        } else {
            $logger err [self] $e

            set response [::tanzer::error response [::tanzer::error fatal]]
        }

        $session send $response

        my close $sock
    }
}

::oo::define ::tanzer::server method accept {sock addr port} {
    my variable config sessions

    fconfigure $sock \
        -translation binary \
        -blocking    0 \
        -buffering   none

    set session [::tanzer::session new [self] $sock $config(proto)]

    $session set sockaddr [list $addr $port]

    fileevent $sock readable [list [self] respond read $sock]

    set sessions($sock) $session

    return
}

::oo::define ::tanzer::server method listen {} {
    my variable config

    socket -server [list [self] accept] $config(port)
}

::oo::define ::tanzer::server method port {} {
    my variable config

    return $config(port)
}
