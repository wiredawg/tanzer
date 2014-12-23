package provide tanzer::cgi::handler 0.1

##
# @file tanzer/cgi/handler.tcl
#
# A request handler providing support for executing CGI/1.1 programs
#

package require tanzer::forwarder
package require tanzer::response
package require tanzer::error
package require TclOO

namespace eval ::tanzer::cgi::handler {
    variable proto           "CGI/1.1"
    variable defaultStatus 200
}

##
# The CGI/1.1 inbound request handler.
#
::oo::class create ::tanzer::cgi::handler {
    superclass ::tanzer::forwarder
}

##
# Create a new CGI/1.1 inbound request handler.
#
# The following values must be specified as a list of key-value pairs in
# `$opts`:
#
# * `program`
#
#   The path to a CGI/1.1 executable.
#
# * `name`
#
#   The script name to report to the CGI/1.1 executable via the `SCRIPT_NAME`
#   environment variable.
#
# * `root`
#
#   The document to report to the CGI/1.1 executable via the `DOCUMENT_ROOT`
#   environment variable.
# .
#
# The CGI/1.1 handler is deliberately meant to provide service for one
# executable, primarily due to security concerns.  However, the flexibility
# afforded by associating an arbitrary route path with any number of these
# request handlers provides advantages over requiring a CGI dispatcher to
# locate scripts in a designated cgi-bin directory.
#
# The CGI/1.1 handler functions simply: After being given the incoming request,
# it executes the CGI program with the appropriate environment variables, and
# parses the CGI program's response into a new ::tanzer::response object, which
# is then sent to the client.  The response body is subsequently passed to the
# client unmodified.
#
::oo::define ::tanzer::cgi::handler constructor {opts} {
    my variable config pipes buffers

    set requirements {
        program "No CGI executable provided"
        name    "No script name provided"
        root    "No document root provided"
    }

    array set config  {}
    array set pipes   {}
    array set buffers {}

    foreach {name message} $requirements {
        if {![dict exists $opts $name]} {
            error "$message in option '$name'"
        }

        set config($name) [dict get $opts $name]
    }
}

::oo::define ::tanzer::cgi::handler method open {session} {
    my variable config pipes buffers

    set server   [$session server]
    set request  [$session request]
    set sock     [$session sock]

    set listener [chan configure $sock -sockname]

    set childenv [dict create \
        GATEWAY_INTERFACE $::tanzer::cgi::handler::proto \
        SERVER_SOFTWARE   "$::tanzer::server::name/$::tanzer::server::version" \
        SERVER_ADDR       [lindex $listener 0] \
        SERVER_HOST       [lindex $listener 1] \
        SERVER_PORT       [lindex $listener 2] \
        SCRIPT_FILENAME   $config(program) \
        SCRIPT_NAME       $config(name) \
        REQUEST_METHOD    [$request method] \
        PWD               [pwd] \
        DOCUMENT_ROOT     $config(root)]

    foreach {name value} [$request env] {
        dict set childenv $name $value
    }

    foreach {name value} [$request headers] {
        dict set childenv \
            "HTTP_[string map {"-" "_"} [string toupper $name]]" \
            $value
    }

    set envargs [list]

    foreach {key value} $childenv {
        lappend envargs "$key=$value"
    }

    set pipe [open [list |/usr/bin/env -i {*}$envargs $config(program)] r+]

    chan configure $pipe    \
        -translation binary \
        -blocking    0      \
        -buffering   full   \
        -buffersize  [$session config readsize]

    set pipes($session)   $pipe
    set buffers($session) ""

    #
    # Bind writable events on the CGI pipe to the server's reader handler.
    #
    $session reset none

    chan event $pipe readable {}
    chan event $pipe writable [list $server respond read [$session sock]]

    #
    # Now, prepare a new, empty response object, and ensure any session state is
    # cleaned up when appropriate.
    #
    $session response -new [::tanzer::response new \
        $::tanzer::cgi::handler::defaultStatus]

    $session cleanup [self] cleanup $session
}

::oo::define ::tanzer::cgi::handler method cleanup {session} {
    my variable pipes buffers

    if {[array get pipes $session] eq {}} {
        return
    }

    catch {
        ::close $pipes($session)
    }

    array unset pipes   $session
    array unset buffers $session

    return
}

::oo::define ::tanzer::cgi::handler method close {session} {
    my cleanup $session

    $session nextRequest

    return
}

::oo::define ::tanzer::cgi::handler method read {session data} {
    my variable pipes

    #
    # Open a pipe to the CGI executable if we have not already done so.
    #
    if {[array get pipes $session] eq {}} {
        my open $session
    }

    #
    # If we have data to buffer for the request body, then let's send that to the
    # CGI executable and quickly return.
    #
    if {[string length $data] > 0} {
        puts -nonewline $pipes($session) data

        return
    }

    #
    # If we've already sent everything out for the request body, we can then bind
    # our own writer to readable events on the CGI pipe.  Of course, the server
    # will only know about the originating client socket, so we'll have to use
    # that as reference for our current request handler.
    #
    set server [$session server]
    set sock   [$session sock]

    chan event $pipes($session) readable [list $server respond write $sock]
    chan event $pipes($session) writable {}

    return
}

::oo::define ::tanzer::cgi::handler method write {session} {
    my variable pipes buffers

    if {[array get pipes $session] eq {}} {
        my open $session
    }

    set pipe $pipes($session)

    set size [$session config readsize]
    set sock [$session sock]

    #
    # If we've already responded to the request, then pipe all remaining data
    # from the CGI process to the client socket, and bail out.
    #
    if {[$session responded]} {
        chan event $pipe readable {}
        chan event $pipe writable {}

        my pipe $pipe $sock $session

        return
    }

    #
    # Read a buffer's worth of data from the CGI subprocess and see if it's a
    # parseable response.
    #
    append buffers($session) [read $pipe $size]

    #
    # If we've received nothing from the CGI program...
    #
    if {[string length $buffers($session)] == 0} {
        #
        # ...And we've reached an EOF condition on that pipe, then move on to the
        # next request.
        #
        if {[eof $pipe]} {
            $session nextRequest
        }

        #
        # And return nonetheless.
        #
        return
    }

    if {![$session response parse buffers($session)]} {
        if {[eof $pipe]} {
            ::tanzer::error throw \
                500 "Could not parse response from CGI program"
        }

        return
    }

    #
    # Let's see if we've received a reasonable header to determine what sort
    # of response status to send off.
    #
    if {[$session response headerExists Status]} {
        #
        # If the CGI program explicitly mentions a Status:, then send that
        # along.
        #
        $session response status [lindex [$session response header Status] 0]
    } elseif {[$session response headerExists Content-Type]} {
        #
        # Presume the CGI response is valid if it is qualified with a type.
        #
        $session response status 200
    } elseif {[$session response headerExists Location]} {
        #
        # Send a 301 Redirect if the CGI program indicated a Location: header.
        #
        $session response status 301
    }

    #
    # Let's send this little piggy to the market.
    #
    $session respond

    #
    # Now, send off everything that's left over in the buffer.
    #
    $session write $buffers($session)

    #
    # And discard the buffer.
    #
    unset buffers($session)

    return
}
