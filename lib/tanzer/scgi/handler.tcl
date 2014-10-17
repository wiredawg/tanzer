package provide tanzer::scgi::handler 0.0.1
package require tanzer::response
package require tanzer::error
package require TclOO
package require Tclx

namespace eval ::tanzer::scgi::handler {
    variable version         1
    variable defaultStatus 500
}

::oo::class create ::tanzer::scgi::handler

::oo::define ::tanzer::scgi::handler constructor {opts} {
    my variable config socks buffers \
        bodies requested responses

    set requirements {
        host "No SCGI service host provided"
        port "No SCGI service port provided"
        name "No program name provided"
    }

    set defaults {
        rewrite {}
    }

    array set config    $defaults
    array set socks     {}
    array set buffers   {}
    array set bodies    {}
    array set requested {}
    array set responses {}

    foreach {name message} $requirements {
        if {![dict exists $opts $name]} {
            error "$message in option '$name'"
        }

        set config($name) [dict get $opts $name]
    }

    foreach {name value} $defaults {
        if {[dict exists $opts $name]} {
            set config($name) [dict get $opts $name]
        }
    }
}

::oo::define ::tanzer::scgi::handler method encodeRequest {session} {
    my variable config bodies

    set server  [$session server]
    set request [$session request]
    set addr    [lindex [chan configure [$session sock] -sockname] 0]

    set env [list \
        SCGI              $::tanzer::scgi::handler::version \
        SERVER_SOFTWARE   "$::tanzer::server::name/$::tanzer::server::version" \
        SERVER_ADDR       $addr \
        SERVER_PORT       [$server port] \
        SCRIPT_NAME       $config(name) \
        REQUEST_METHOD    [$request method] \
        PWD               [pwd]]

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
    my variable config socks buffers \
        requested responses

    set request [$session request]

    if {[array get config rewrite] ne {}} {
        foreach {re newFormat} $config(rewrite) {
            if {[$request rewrite $re $newFormat]} {
                break
            }
        }
    }

    set sock [socket $config(host) $config(port)]

    fconfigure $sock \
        -translation binary \
        -buffering   none

    set socks($session)     $sock
    set buffers($session)   ""
    set bodies($session)    ""
    set requested($session) 0
    set responses($session) [::tanzer::response new \
        $::tanzer::scgi::handler::defaultStatus]

    $session cleanup [self] cleanup $session
}

::oo::define ::tanzer::scgi::handler method cleanup {session} {
    my variable socks buffers bodies \
        requested responses

    if {[array get socks $session] eq {}} {
        return
    }

    ::close $socks($session)

    array unset socks     $session
    array unset buffers   $session
    array unset bodies    $session
    array unset requested $session
    array unset requested $session
    array unset responses $session

    return
}

::oo::define ::tanzer::scgi::handler method close {session} {
    my cleanup $session

    $session nextRequest

    return
}

::oo::define ::tanzer::scgi::handler method respond {event session data} {
    my variable config socks buffers \
        bodies requested responses

    if {[array get socks $session] eq {}} {
        my open $session
    }

    set response $responses($session)

    if {$event eq "read"} {
        append bodies($session) $data

        return
    }

    if {$event ne "write"} {
        error "Invalid event $event"
    }

    #
    # If we have not forwarded the HTTP request to the SCGI service, then do
    # so.
    #
    if {!$requested($session)} {
        puts -nonewline $socks($session) [my encodeRequest $session]

        set requested($session) 1
    }

    set size [$session config readBufferSize]
    set sock [$session sock]

    #
    # If we weren't able to read anything from the SCGI service, then let's
    # wrap up this session.
    #
    if {[$session responded]} {
        fcopy $socks($session) $sock -size $size

        if {[eof $socks($session)]} {
            my close $session
        }

        return
    }

    #
    # Read a buffer's worth of data from the CGI subprocess and see if it's a
    # parseable response.
    #
    set buf [read $socks($session) $size]

    append buffers($session) $buf

    if {![$response parse $buffers($session)]} {
        return
    }

    #
    # Let's send this little piggy to the market.
    #
    $session send $response

    #
    # Now, send off everything that's left over in the buffer, after the
    # headers.
    #
    $session write [string range $buffers($session) \
        [expr {[$response headerLength] + 4}] end]

    #
    # And discard the buffer cruft.
    #
    unset buffers($session)

    return
}
