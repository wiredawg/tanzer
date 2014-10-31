package provide tanzer::cgi::handler 0.1
package require tanzer::forwarder
package require tanzer::response
package require tanzer::error
package require TclOO

namespace eval ::tanzer::cgi::handler {
    variable proto "CGI/1.1"
}

::oo::class create ::tanzer::cgi::handler {
    superclass ::tanzer::forwarder
}

::oo::define ::tanzer::cgi::handler constructor {opts} {
    my variable config pipes buffers responses

    next $opts

    set requirements {
        program "No CGI executable provided"
        name    "No script name provided"
        root    "No document root provided"
    }

    array set config    {}
    array set pipes     {}
    array set buffers   {}
    array set responses {}

    foreach {name message} $requirements {
        if {![dict exists $opts $name]} {
            error "$message in option '$name'"
        }

        set config($name) [dict get $opts $name]
    }
}

::oo::define ::tanzer::cgi::handler method open {session} {
    my variable config pipes buffers responses

    next $session

    set server  [$session server]
    set route   [$session route]
    set request [$session request]

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

    set envargs [list]

    foreach {key value} $childenv {
        lappend envargs "$key=$value"
    }

    set pipe [open [list |/usr/bin/env -i {*}$envargs $config(program)] r+]

    fconfigure $pipe \
        -translation binary \
        -buffering   none \
        -blocking    1

    set pipes($session)     $pipe
    set buffers($session)   ""
    set responses($session) [::tanzer::response new \
        $::tanzer::forwarder::defaultStatus]

    $responses($session) setup -newline "\n"

    $session cleanup [self] cleanup $session
}

::oo::define ::tanzer::cgi::handler method cleanup {session} {
    my variable pipes buffers responses

    if {[array get pipes $session] eq {}} {
        return
    }

    catch {
        ::close $pipes($session)
    }

    array unset pipes     $session
    array unset buffers   $session
    array unset responses $session

    return
}

::oo::define ::tanzer::cgi::handler method close {session} {
    my cleanup $session

    $session nextRequest

    return
}

::oo::define ::tanzer::cgi::handler method read {session data} {
    my variable pipes

    if {[array get pipes $session] eq {}} {
        my open $session
    }

    puts -nonewline $pipes($session) $data
}

::oo::define ::tanzer::cgi::handler method write {session} {
    my variable pipes buffers responses

    if {[array get pipes $session] eq {}} {
        my open $session
    }

    set pipe     $pipes($session)
    set response $responses($session)

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
        fcopy $pipe $sock -size $size

        if {[eof $pipe]} {
            my close $session
        }

        return
    }

    #
    # Read a buffer's worth of data from the CGI subprocess and see if it's a
    # parseable response.
    #
    append buffers($session) [read $pipe $size]

    if {![$response parse buffers($session)]} {
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
    # Now, send off everything that's left over in the buffer.
    #
    $session write $buffers($session)

    #
    # And discard the buffer.
    #
    unset buffers($session)

    return
}
