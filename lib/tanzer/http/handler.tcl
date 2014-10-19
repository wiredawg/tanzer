package provide tanzer::http::handler 0.0.1
package require tanzer::forwarder
package require tanzer::response
package require tanzer::error
package require TclOO

::oo::class create ::tanzer::http::handler {
    superclass ::tanzer::forwarder
}

::oo::define ::tanzer::http::handler constructor {opts} {
    my variable config socks buffers \
        lengths requested responses

    next $opts

    set requirements {
        host "No HTTP service host provided"
        port "No HTTP service port provided"
    }

    array set config {}

    foreach varName {socks buffers lengths requested responses} {
        array set $varName {}
    }

    foreach {name message} $requirements {
        if {![dict exists $opts $name]} {
            error "$message in option '$name'"
        }

        set config($name) [dict get $opts $name]
    }
}

::oo::define ::tanzer::http::handler method open {session} {
    my variable config socks buffers \
        requested responses

    next $session

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
        -blocking    0 \
        -buffering   none

    set socks($session)     $sock
    set buffers($session)   ""
    set lengths($session)   0
    set requested($session) 0
    set responses($session) [::tanzer::response new \
        $::tanzer::forwarder::defaultStatus]

    $session cleanup [self] cleanup $session
}

::oo::define ::tanzer::http::handler method cleanup {session} {
    my variable socks buffers requested responses

    if {[array get socks $session] eq {}} {
        return
    }

    ::close $socks($session)

    array unset socks     $session
    array unset buffers   $session
    array unset lengths   $session
    array unset requested $session
    array unset responses $session

    return
}

::oo::define ::tanzer::http::handler method close {session} {
    my cleanup $session

    $session nextRequest

    return
}

::oo::define ::tanzer::http::handler method read {session data} {
    my variable socks

    if {[array get socks $session] eq {}} {
        my open $session
    }

    [$session request] buffer $data
}

::oo::define ::tanzer::http::handler method write {session} {
    my variable socks buffers lengths \
        requested responses

    $session tick

    set request  [$session request]
    set response $responses($session)

    #
    # If we have not forwarded the HTTP request to the remote server, then do
    # so.
    #
    if {!$requested($session)} {
        $request send $socks($session)

        set requested($session) 1

        fileevent [$session sock] readable {}
        fileevent [$session sock] writable {}

        fileevent $socks($session) readable [list [self] write $session]
        fileevent $socks($session) writable {}

        return
    }

    set size [$session config readBufferSize]
    set sock [$session sock]

    if {[$session responded]} {
        set len [expr {
            $size > $lengths($session)? $lengths($session): $size
        }]

        incr lengths($session) -[fcopy $socks($session) $sock -size $len]

        if {[eof $socks($session)] || $lengths($session) == 0} {
            my close $session
        }

        return
    }

    #
    # If we weren't able to read anything from the HTTP service, then let's
    # wrap up this session.
    #
    if {[eof $socks($session)]} {
        my close $session
    }

    #
    # Read a buffer's worth of data from the HTTP service and see if it's a
    # parseable response.
    #
    append buffers($session) [read $socks($session) $size]

    if {![$response parse $buffers($session)]} {
        return
    }

    set lengths($session) [$response length]

    #
    # Let's send this little piggy to the market.
    #
    $session send $response

    #
    # Now, send off everything that's left over in the buffer, after the
    # headers.
    #
    incr lengths($session) -[$session write [string range $buffers($session) \
        [expr {[$response headerLength] + 4}] end]]

    #
    # And discard the buffer cruft.
    #
    unset buffers($session)

    return
}
