package provide tanzer::scgi::handler 0.1

##
# @file tanzer/scgi/handler.tcl
#
# The SCGI client request handler
#

package require tanzer::forwarder
package require tanzer::response
package require tanzer::error
package require TclOO

namespace eval ::tanzer::scgi::handler {
    variable version 1
}

##
# The SCGI client, implemented as a request handler.
#
::oo::class create ::tanzer::scgi::handler {
    superclass ::tanzer::forwarder
}

##
# The following values must be provided in a list of key-value pairs listed in
# `$opts`.
#
# * `host`
#
#   The hostname or address of the SCGI service to dispatch requests to.
#
# * `port`
#
#   The TCP port of the SCGI service to dispatch requests to.
#
# * `name`
#
#   The name of the script that shall be identified to the service via the
#   `SCRIPT_NAME` SCGI request parameter.
#
# * `root`
#
#   The location of a document root that shall be identified to the service via
#   the `DOCUMENT_ROOT` SCGI request parameter.
# .
#
# All inbound requests are transformed into an SCGI request as per the official
# SCGI protocol specificaton:
#
#     http://python.ca/scgi/protocol.txt
#
# The response from the SCGI service is parsed into a ::tanzer::response
# message object, and sent by the session handler to the client.  In all cases,
# this request handler shall forward request to the remote service, and
# response bodies from the SCGI service to the originating client.
#
::oo::define ::tanzer::scgi::handler constructor {opts} {
    my variable config socks bodies buffers requested

    set requirements {
        host "No SCGI service host provided"
        port "No SCGI service port provided"
        name "No program name provided"
    }

    set optional {
        root
    }

    array set config    {}
    array set socks     {}
    array set bodies    {}
    array set buffers   {}
    array set requested {}

    foreach {name message} $requirements {
        if {![dict exists $opts $name]} {
            error "$message in option '$name'"
        }

        set config($name) [dict get $opts $name]
    }

    foreach name $optional {
        if {[dict exists $opts $name]} {
            set config($name) [dict get $opts $name]
        }
    }
}

##
# Not meant to be called directly.
#
# Given the session handler specified in `$session`, serialize the current
# request into an SCGI protocol request return value.
#
::oo::define ::tanzer::scgi::handler method open {session} {
    my variable config socks bodies buffers requested

    set server  [$session server]
    set request [$session request]
    set sock    [socket $config(host) $config(port)]

    chan configure $sock    \
        -translation binary \
        -blocking    0      \
        -buffering   full   \
        -buffersize  [$session config readsize]

    set socks($session)     $sock
    set bodies($session)    ""
    set buffers($session)   ""
    set requested($session) 0

    #
    # Bind writable events on the SCGI socket to the server's reader handler.
    #
    $session reset none

    chan event $sock readable {}
    chan event $sock writable [list $server respond read [$session sock]]

    #
    # Now, prepare a new, empty response object, and ensure any session state
    # is cleaned up when appropriate.
    #
    $session response -new [::tanzer::response new \
        $::tanzer::forwarder::defaultStatus]

    $session cleanup [self] cleanup $session
}

::oo::define ::tanzer::scgi::handler method encodeRequest {session} {
    my variable config bodies

    set server  [$session server]
    set request [$session request]
    set addr    [lindex [chan configure [$session sock] -sockname] 0]

    set env [list \
        SCGI            $::tanzer::scgi::handler::version                    \
        SERVER_SOFTWARE "$::tanzer::server::name/$::tanzer::server::version" \
        CONTENT_LENGTH  [string length $bodies($session)]                    \
        SCRIPT_NAME     $config(name)                                        \
        REQUEST_METHOD  [$request method]                                    \
        PWD             [pwd]]

    if {[array get config root] ne {}} {
        lappend env DOCUMENT_ROOT $config(root)
    }

    foreach {name value} [$request env] {
        lappend env $name $value
    }

    foreach {name value} [$request headers] {
        lappend env \
            "HTTP_[string map {"-" "_"} [string toupper $name]]" \
            $value
    }

    set data ""

    foreach {name value} $env {
        append data "$name\x00$value\x00"
    }

    return "[string length $data]:$data,"
}

::oo::define ::tanzer::scgi::handler method cleanup {session} {
    my variable socks bodies buffers

    if {[array get socks $session] eq {}} {
        return
    }

    catch {
        ::close $socks($session)
    }

    array unset socks   $session
    array unset bodies  $session
    array unset buffers $session

    return
}

::oo::define ::tanzer::scgi::handler method close {session} {
    my cleanup $session

    $session nextRequest

    return
}

::oo::define ::tanzer::scgi::handler method read {session data} {
    my variable socks bodies requested

    #
    # Open a connection to the remote SCGI service if we have not already done
    # so.
    #
    if {[array get socks $session] eq {}} {
        my open $session

        return
    }

    #
    # If we have data to buffer for the request body, then let's buffer that
    # and quickly return.
    #
    if {[string length $data] > 0} {
        append bodies($session) $data

        return
    }

    #
    # If we have no more data, and we have not sent our request to the remote
    # SCGI service, then do so.
    #
    if {!$requested($session)} {
        puts -nonewline $socks($session) [my encodeRequest $session]
        flush $socks($session)

        set requested($session) 1

        return
    }

    #
    # If we've already sent everything out for the buffered session body, then
    # we can bind our writer to readable events on the SCGI socket.  Of course,
    # the server will only know about the originating client socket, so we'll
    # have to use that as reference for our current request handler.
    #
    if {[string length $bodies($session)] == 0} {
        set server [$session server]
        set sock   [$session sock]

        chan event $socks($session) readable [list $server respond write $sock]
        chan event $socks($session) writable {}

        return
    }

    #
    # Otherwise, let's send the request body to the SCGI service in chunks.
    #
    set size [$session config readsize]

    puts -nonewline $socks($session) [string range $bodies($session) \
        0 [expr {$size - 1}]]

    #
    # Truncate that amount off the beginning of the body.
    #
    set bodies($session) [string range $bodies($session) \
        $size end]
}

::oo::define ::tanzer::scgi::handler method write {session} {
    my variable socks buffers

    set size [$session config readsize]
    set sock [$session sock]

    #
    # If we weren't able to read anything from the SCGI service, then let's
    # wrap up this session; [my pipe] will end the session once it has finished
    # funneling data from the SCGI socket to the client socket.
    #
    if {[$session responded]} {
        chan event $socks($session) readable {}
        chan event $socks($session) writable {}

        my pipe $socks($session) $sock $session

        return
    }

    #
    # Read a buffer's worth of data from the CGI subprocess and see if it's a
    # parseable response.
    #
    set buf [read $socks($session) $size]

    append buffers($session) $buf

    #
    # If we've received nothing from the remote SCGI service...
    #
    if {[string length $buffers($session)] == 0} {
        #
        # ...And we've reached an EOF condition on that socket, then move on to
        # the next request.
        #
        if {[eof $socks($session)]} {
            $session nextRequest
        }

        #
        # But nonetheless return.
        #
        return
    }

    if {![$session response parse buffers($session)]} {
        if {[eof $socks($session)]} {
            ::tanzer::error throw \
                500 "Could not parse response from SCGI service"
        }

        return
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
    # And discard the buffer cruft.
    #
    unset buffers($session)

    return
}
