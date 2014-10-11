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
    my variable config buffers

    set requirements {
        program "No CGI executable provided"
        name    "No script name provided"
        root    "No document root provided"
    }

    set defaults {
        rewrite {}
    }

    array set config $defaults

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
    my variable config pipes buffers

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

    set buffers($session) ""

    $session cleanup [self] cleanup $session
}

::oo::define ::tanzer::cgi::handler method cleanup {session} {
    my variable pipes buffers

    if {[array get pipes $session] eq {}} {
        return
    }

    foreach name {in out pid} {
        set $name [dict get $pipes($session) $name]
    }

    ::close $in
    ::close $out
    wait  $pid

    array unset pipes   $session
    array unset buffers $session

    return
}

::oo::define ::tanzer::cgi::handler method close {session} {
    my cleanup $session

    $session nextRequest

    return
}

::oo::define ::tanzer::cgi::handler method respond {event session data} {
    my variable config pipes buffers

    if {[array get pipes $session] eq {}} {
        my open $session
    }

    set pipe $pipes($session)
    set in   [dict get $pipe in]
    set out  [dict get $pipe out]

    if {$event eq "read"} {
        puts -nonewline $in $data

        return
    }

    if {$event ne "write"} {
        error "Invalid event $event"
    }

    set buf [read $out [$session config readBufferSize]]

    #
    # If we weren'ta ble to read anything from the CGI process, then let's wrap
    # up this session.
    #
    #
    # If we've already sent out a response, then just ferry data between the
    # server process and the CGI process, and move on.
    #
    if {[$session response] ne {}} {
        $session write $buf

        if {[eof $out]} {
            my close $session
        }

        return
    }

    #
    # Otherwise, we need to buffer the data until we've read enough to parse
    # the response headers.
    #
    append buffers($session) $buf

    #
    # Let's check and see if we've found the end of the response headers yet.
    #
    set headerLength [string first "\n\n" $buffers($session)]

    #
    # If we've not found the end of the request headers yet, then let's bail
    # for now.
    #
    if {$headerLength < 0} {
        #
        # Furthermore, let's bail this entire session if our current read
        # buffer is empty.
        #
        if {$buf eq ""} {
            ::tanzer::error throw 500 "Invalid response"
        }

        return
    }

    #
    # Now's a great time to parse.
    #
    # I feel like I've written this code already.  And, it just so happens to
    # be the case, I already *have*.  So, XXX TODO: PLEASE REFACTOR THE CODE
    # HERE AND IN ::tanzer::http::request TO BE SOMEWHERE SHARED, K? <3
    #
    set status  200
    set headers [dict create]

    set preamble    [string range $buffers($session) 0 $headerLength]
    set headerName  {}
    set headerValue {}

    set start 0
    set end   [expr {[string first "\n" $preamble $start] - 1}]

    while {1} {
        set line [string range $preamble $start $end]

        if {[regexp -nocase {^([a-z][a-z0-9\-_]+):\s+(.*)} $line {} newHeaderName newHeaderValue]} {
            #
            # Set the value of an existing header that was parsed previously.
            #
            if {$headerName ne {} && $headerValue ne {}} {
                dict set headers $headerName $headerValue
            }

            set headerName $newHeaderName
            set headerValue [string trim $newHeaderValue]
        } elseif {[regexp {^\s+(.*)$} $line {} headerValueExtra]} {
            #
            # Look for header value continuation lines.
            #
            if {$headerName eq {}} {
                ::tanzer::error throw 500 "Invalid response"
            }

            append headerValue [string trim $headerValueExtra]
        } else {
            ::tanzer::error throw 500 "Invalid response format"
        }

        set start [expr {$end + 2}]
        set end   [expr {[string first "\n" $preamble $start] - 1}]

        if {$end < 0} {
            break
        }
    }

    #
    # Set remaining headers at the end of the response.
    #
    if {$headerName ne {} && $headerValue ne {}} {
        dict set headers $headerName $headerValue
    }

    #
    # If there are no reasonable headers, then that's bad, mmmkay?
    #


    #
    # Prepare a response object.
    #
    set response [::tanzer::response new $status $headers]

    #
    # Let's see if we've received a reasonable header to determine what sort
    # of response status to send off.
    #
    if {[$response headerExists Status]} {
        #
        # If the CGI program explicitly mentions a Status:, then send that
        # along.
        #
        $response code [lindex [$response header Status] 0]
    } elseif {[$response headerExists Location]} {
        #
        # In this event, we ought to emit a 301 redirect.
        #
        $response code 301
    }

    #
    # On the other hand, we need to check if we actually know the length of the
    # response.  If we don't, then we should tell the session to die after
    # servicing this request, because the client will likely expect more data.
    #
    if {![$response headerExists Content-Length]} {
        $session keepalive 0
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
        [expr {$headerLength + 2}] end]

    #
    # And discard the buffer cruft.
    #
    unset buffers($session)

    return
}
