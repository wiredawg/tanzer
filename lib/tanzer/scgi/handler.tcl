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
    my variable config socks buffers bodies requested

    next $opts

    set requirements {
        host "No SCGI service host provided"
        port "No SCGI service port provided"
        name "No program name provided"
    }

    array set config    {}
    array set socks     {}
    array set buffers   {}
    array set bodies    {}
    array set requested {}

    foreach {name message} $requirements {
        if {![dict exists $opts $name]} {
            error "$message in option '$name'"
        }

        set config($name) [dict get $opts $name]
    }
}

##
# Not meant to be called directly.
#
# Given the session handler specified in `$session`, serialize the current
# request into an SCGI protocol request return value.
#
::oo::define ::tanzer::scgi::handler method encodeRequest {session} {
    my variable config bodies

    set server  [$session server]
    set request [$session request]
    set addr    [lindex [chan configure [$session sock] -sockname] 0]

    set env [list \
        SCGI            $::tanzer::scgi::handler::version \
        SERVER_SOFTWARE "$::tanzer::server::name/$::tanzer::server::version" \
        SERVER_ADDR     $addr \
        SERVER_PORT     [$server port] \
        SCRIPT_NAME     $config(name) \
        REQUEST_METHOD  [$request method] \
        PWD             [pwd]]

    lappend env CONTENT_LENGTH [string length $bodies($session)]

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

::oo::define ::tanzer::scgi::handler method open {session} {
    my variable config socks buffers requested

    next $session

    set request [$session request]
    set sock    [socket $config(host) $config(port)]

    fconfigure $sock \
        -translation binary \
        -blocking    0 \
        -buffering   full \
        -buffersize  [$session config readsize]

    set socks($session)     $sock
    set buffers($session)   ""
    set bodies($session)    ""
    set requested($session) 0

    $session respond -new [::tanzer::response new \
        $::tanzer::forwarder::defaultStatus]

    $session cleanup [self] cleanup $session
}

::oo::define ::tanzer::scgi::handler method cleanup {session} {
    my variable socks buffers bodies requested

    if {[array get socks $session] eq {}} {
        return
    }

    catch {
        ::close $socks($session)
    }

    array unset socks     $session
    array unset buffers   $session
    array unset bodies    $session
    array unset requested $session
    array unset requested $session

    return
}

::oo::define ::tanzer::scgi::handler method close {session} {
    my cleanup $session

    $session nextRequest

    return
}

::oo::define ::tanzer::scgi::handler method read {session data} {
    my variable socks bodies

    if {[array get socks $session] eq {}} {
        my open $session
    }

    append bodies($session) $data
}

::oo::define ::tanzer::scgi::handler method pipe {in out} {

}

::oo::define ::tanzer::scgi::handler method write {session} {
    my variable socks buffers requested

    #
    # If we have not forwarded the HTTP request to the SCGI service, then do
    # so.
    #
    if {!$requested($session)} {
        puts -nonewline $socks($session) [my encodeRequest $session]
        flush $socks($session)

        set requested($session) 1
    }

    set size [$session config size]
    set sock [$session sock]

    #
    # If we weren't able to read anything from the SCGI service, then let's
    # wrap up this session.
    #
    if {[$session responded]} {
        my pipe $socks($session) $sock $session

        return
    }

    #
    # Read a buffer's worth of data from the CGI subprocess and see if it's a
    # parseable response.
    #
    set buf [read $socks($session) $size]

    append buffers($session) $buf

    if {![$session response parse buffers($session)]} {
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
