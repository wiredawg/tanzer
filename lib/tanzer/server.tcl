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

##
# Route a request handler to the server.  Arguments are as follows:
#
# - `$method`
#
#   A non-anchored regular expression performing a case insensitive match on
#   the incoming HTTP request method.  Anchoring is performed by the request
#   route matching engine.
#
# - `$pattern`
#
#   A URI path, containing any number of path components describing named
#   parameters in the `:param` style.  Paths ending with `*` will match any
#   incoming URI path parts before the glob.
#
# - `$host`
#
#   A non-anchored regular expression performing a case insensitive match on
#   the incoming HTTP Host: request header.  Anchoring is performed by the
#   request route matching engine.
#
# - `$args`
#
#   Any number of arguments desribing the request handler to be dispatched
#   for requests that match the route described by an invocation to this
#   method.
#
#   The following arguments will be appended to the script specified in
#   `$args`:
#
#   - An event, `read` or `write`, indicating the session socket is ready to be
#     read from or written to
#
#   - A reference to a `::tanzer::session` object
#
#   - When dispatching a `read` event, a chunk of data read from the request
#     body
#
#   .
# .
#
::oo::define ::tanzer::server method route {method pattern host args} {
    my variable routes

    lappend routes [::tanzer::route new $method $pattern $host $args]
}

##
# Return a list of the current routed request handlers.
#
::oo::define ::tanzer::server method routes {} {
    my variable routes

    return $routes
}

##
# Make the server completely forget about `$sock`.  The server will forget
# about the session handler associated with the socket.
#
::oo::define ::tanzer::server method forget {sock} {
    my variable sessions

    if {[array get sessions $sock] eq {}} {
        return
    }

    unset sessions($sock)
}

##
# Close socket `$sock`, destroy the associated session handler, and forget
# about the socket and session handler.
#
::oo::define ::tanzer::server method close {sock} {
    my variable sessions

    if {[array get sessions $sock] eq {}} {
        return
    }

    $sessions($sock) destroy

    my forget $sock
}

##
# The default I/O event handler associated with new connection sockets opened
# by the server.  `$event` is one of `read` or `write`.  Not meant to be called
# directly.
#
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

##
# The callback to `[socket -server]`.  Creates a new ::tanzer::session
# object associated with `$sock`, and stores the remote address and socket
# port for `$sock` in the new session object.  The default event handler will
# be installed for `$sock` for only `read` events.
#
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

##
# Starts the server.  Incoming connections are passed on to @ref accept.
#
::oo::define ::tanzer::server method listen {} {
    my variable config

    socket -server [list [self] accept] $config(port)
}

##
# Returns the TCP port the server is configured to listen on.
#
::oo::define ::tanzer::server method port {} {
    my variable config

    return $config(port)
}
