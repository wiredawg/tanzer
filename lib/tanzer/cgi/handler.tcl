package provide tanzer::cgi::handler 0.0.1
package require tanzer::response
package require tanzer::error
package require TclOO
package require Tclx

namespace eval ::tanzer::cgi::handler {
    variable proto         "CGI/1.1"
    variable defaultStatus 500
}

::oo::class create ::tanzer::cgi::handler

::oo::define ::tanzer::cgi::handler constructor {opts} {
    my variable config pipes buffers responses

    set requirements {
        program "No CGI executable provided"
        name    "No script name provided"
        root    "No document root provided"
    }

    set defaults {
        rewrite {}
    }

    array set config    $defaults
    array set pipes     {}
    array set buffers   {}
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

::oo::define ::tanzer::cgi::handler method open {session} {
    my variable config pipes buffers responses

    set server  [$session server]
    set route   [$session route]
    set request [$session request]

    if {[array get config rewrite] ne {}} {
        foreach {re newFormat} $config(rewrite) {
            if {[$request rewrite $re $newFormat]} {
                break
            }
        }
    }

    set addr [lindex [chan configure [$session sock] -sockname] 0]

    set childenv [dict create \
        GATEWAY_INTERFACE $::tanzer::cgi::handler::proto \
        SERVER_SOFTWARE   "$::tanzer::server::name/$::tanzer::server::version" \
        SERVER_ADDR       $addr \
        SERVER_PORT       [$server port] \
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

    pipe stdin_r  stdin_w
    pipe stdout_r stdout_w

    foreach fh [list $stdin_r $stdin_w $stdout_r $stdout_w] {
        fconfigure $fh \
            -translation binary \
            -blocking    0
    }

    fcntl $stdin_w  NOBUF 1
    fcntl $stdout_r NOBUF 1

    set child [fork]

    if {$child == 0} {
        close $stdin_w
        close $stdout_r

        dup $stdin_r  stdin
        dup $stdout_w stdout

        foreach {name unused} [array get ::env] {
            unset ::env($name)
        }

        array set ::env $childenv

        execl $config(program)

        exit 127
    }

    close $stdin_r
    close $stdout_w

    set pipes($session) [dict create \
        in  $stdin_w \
        out $stdout_r \
        pid $child]

    set buffers($session)   ""
    set responses($session) [::tanzer::response new \
        $::tanzer::cgi::handler::defaultStatus]

    $responses($session) config -newline "\n"

    $session cleanup [self] cleanup $session
}

::oo::define ::tanzer::cgi::handler method cleanup {session} {
    my variable pipes buffers responses

    if {[array get pipes $session] eq {}} {
        return
    }

    foreach name {in out pid} {
        set $name [dict get $pipes($session) $name]
    }

    ::close $in
    ::close $out
    wait $pid

    array unset pipes    $session
    array unset buffers  $session
    array unset responses $session

    return
}

::oo::define ::tanzer::cgi::handler method close {session} {
    my cleanup $session

    $session nextRequest

    return
}

::oo::define ::tanzer::cgi::handler method read {session data} {
    my variable pipes responses

    if {[array get pipes $session] eq {}} {
        my open $session
    }

    set pipe     $pipes($session)
    set response $responses($session)
    set in       [dict get $pipe in]
    set out      [dict get $pipe out]

    puts -nonewline $in $data
}

::oo::define ::tanzer::cgi::handler method write {session} {
    my variable pipes buffers responses

    if {[array get pipes $session] eq {}} {
        my open $session
    }

    set pipe     $pipes($session)
    set response $responses($session)
    set in       [dict get $pipe in]
    set out      [dict get $pipe out]

    set size [$session config readBufferSize]
    set sock [$session sock]

    #
    # If we weren't able to read anything from the CGI process, then let's wrap
    # up this session.
    #
    #
    # If we've already sent out a response, then just ferry data between the
    # server process and the CGI process, and move on.
    #
    if {[$session responded]} {
        fcopy $out $sock -size $size

        if {[eof $out]} {
            my close $session
        }

        return
    }

    #
    # Read a buffer's worth of data from the CGI subprocess and see if it's a
    # parseable response.
    #
    set buf [read $out $size]

    append buffers($session) $buf

    if {![$response parse $buffers($session)]} {
        return
    }

    #
    # Let's see if we've received a reasonable header to determine what sort
    # of response status to send off.
    #
    if {[$response headerExists Status]} {
        #
        # If the CGI program explicitly mentions a Status:, then send that
        # along.
        #
        $response status [lindex [$response header Status] 0]
    } elseif {[$response headerExists Content-Type]} {
        #
        # Presume the CGI response is valid if it is qualified with a type.
        #
        $response status 200
    } elseif {[$response headerExists Location]} {
        #
        # Send a 301 Redirect if the CGI program indicated a Location: header.
        #
        $response status 301
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
        [expr {[$response headerLength] + 2}] end]

    #
    # And discard the buffer cruft.
    #
    unset buffers($session)

    return
}
