package provide tanzer::message 0.1
package require TclOO

namespace eval ::tanzer::message {
    variable maxLength 1048576
    variable defaultVersion   "HTTP/1.1"
}

proc ::tanzer::message::supportedVersion {version} {
    switch $version {
        "HTTP/0.9" -
        "HTTP/1.0" -
        "HTTP/1.1" {
            return 1
        }
    }

    return 0
}

proc ::tanzer::message::field {name} {
    set parts [split $name -]
    set new   [list]

    foreach part $parts {
        lappend new [string toupper [string tolower $part] 0 0]
    }

    return [join $new -]
}

::oo::class create ::tanzer::message

::oo::define ::tanzer::message constructor {args} {
    my variable opts ready chunked data version

    set ready   0
    set chunked ""
    set data    {}
    set version $::tanzer::message::defaultVersion
    
    array set opts {
        newline      "\r\n"
        newlinelen     2
        request        0
        response       0
        errorStatus  400
        errorMessage "Invalid Request"
    }

    if {[llength $args] > 0} {
        my config {*}$args
    }
}

::oo::define ::tanzer::message method config {args} {
    my variable opts

    if {[llength $args] == 0} {
        return [array get opts]
    }

    set prev {}

    foreach arg $args {
        switch -- $arg "-newline" {
            # Needs value
        } "-request" {
            set opts(request) 1
            break
        } "-response" {
            set opts(response)   1
            set errorStatus    500
            set errorMessage     "Invalid Response"

            break
        } default {
            switch -- $prev {} {
                # Do nothing
            } "-newline" {
                set opts(newline)    $arg
                set opts(newlinelen) [string length $arg]
            } default {
                error "Invalid argument $arg"
            }
        }

        set prev $arg
    }

    return
}

::oo::define ::tanzer::message method ready {} {
    my variable ready

    return $ready
}

::oo::define ::tanzer::message method incomplete {} {
    my variable ready

    return [expr {$ready == 0}]
}

::oo::define ::tanzer::message method parse {varName} {
    my variable opts version status ready env headers \
        path uri headerLength

    if {$ready} {
        return 1
    }

    upvar 1 $varName buffer

    set bufferLength [string length $buffer]
    set headerLength [string first "$opts(newline)$opts(newline)" $buffer]
    set bodyStart    [expr {$headerLength + (2 * $opts(newlinelen))}]

    #
    # If we cannot find the end of the headers, then determine if the buffer
    # is too large at this point, and raise an error.  Otherwise, let's try
    # and buffer more data at the next opportunity to reqd the request and
    # have another go at this.
    #
    if {$headerLength < 0} {
        if {$bufferLength >= $tanzer::message::maxLength} {
            ::tanzer::error throw $opts(errorStatus) "Message too large"
        }

        return 0
    }

    #
    # On the other hand, at this point, we happen to know where the request
    # preamble ends.  Let's try to parse that.
    #
    set preamble    [string range $buffer 0 [expr {$headerLength + 1}]]
    set action      {}
    set headerName  {}
    set headerValue {}

    set index 0
    set start 0
    set end   [expr {[string first $opts(newline) $preamble $start] - 1}]

    while {$end > 0} {
        set line [string range $preamble $start $end]

        if {[regexp -nocase {^HTTP/(?:0.9|1.0|1.1)\s+} $line {}]} {
            if {!$opts(response) || $index != 0} {
                ::tanzer::error throw $opts(errorStatus) $opts(errorMessage)
            }

            set responseParts [regexp -all -inline {\S+} $line]
            set partCount     [llength $responseParts]

            if {$partCount < 2} {
                ::tanzer::error throw 500 "Malformed HTTP response"
            }

            lassign $responseParts version status
        } elseif {[regexp -nocase {^(?:[a-z]+)\s+} $line {}]} {
            if {!$opts(request) || $action ne {} || $index != 0} {
                ::tanzer::error throw $opts(errorStatus) $opts(errorMessage)
            }

            #
            # Look for the request action, first.
            #
            set action    [regexp -all -inline {\S+} $line]
            set partCount [llength $action]

            if {$partCount > 3 || $partCount < 2} {
                ::tanzer::error throw 400 "Malformed HTTP request"
            }

            lassign $action httpMethod httpUri httpVersion

            if {$httpVersion eq {}} {
                set httpVersion $::tanzer::message::defaultVersion
            }

            if {![::tanzer::message::supportedVersion $httpVersion]} {
                ::tanzer::error throw 400 "Bad HTTP version $httpVersion"
            }

            my env REQUEST_METHOD  $httpMethod
            my env SERVER_PROTOCOL $httpVersion

            my uri $httpUri
        } elseif {[regexp -nocase {^([a-z][a-z0-9\-_]+):\s+(.*)} $line {} newHeaderName newHeaderValue]} {
            #
            # Set the value of an existing header that was parsed previously.
            #
            if {$headerName ne {} && $headerValue ne {}} {
                my header $headerName $headerValue
            }

            set headerName  $newHeaderName
            set headerValue [string trim $newHeaderValue]
        } elseif {[regexp {^\s+(.*)$} $line {} headerValueExtra]} {
            #
            # Look for header value continuation lines.
            #
            if {$headerName eq {}} {
                ::tanzer::error throw $opts(errorStatus) $opts(errorMessage)
            }

            append headerValue " [string trim $headerValueExtra]"
        } else {
            ::tanzer::error throw $opts(errorStatus) $opts(errorMessage)
        }

        set start [expr {$end + $opts(newlinelen) + 1}]
        set end   [expr {[string first "\r\n" $preamble $start] - 1}]

        incr index
    }

    #
    # Set remaining headers at the end of the request.
    #
    if {$headerName ne {} && $headerValue ne {}} {
        my header $headerName $headerValue
    }

    #
    # Truncate the header data from the buffer, now.
    #
    set buffer [string range $buffer $bodyStart end]

    #
    # Finally, update the ready flag to indicate that the request is now
    # usable to the session handler.
    #
    set ready 1

    #
    # Tell the caller that we've successfully parsed the request.
    #
    return 1
}

::oo::define ::tanzer::message method version {{newVersion ""}} {
    my variable version

    if {$newVersion ne ""} {
        set version $newVersion

        return
    }

    return $version
}

::oo::define ::tanzer::message method uri {args} {
    error "Not implemented"
}

::oo::define ::tanzer::message method headerLength {} {
    my variable headerLength

    return $headerLength
}

::oo::define ::tanzer::message method header {name {value ""}} {
    my variable headers

    set name [::tanzer::message::field $name]

    if {$value ne ""} {
        dict set headers $name $value

        return
    }

    return [dict get $headers $name]
}

::oo::define ::tanzer::message method headers {{newHeaders {}}} {
    my variable headers

    if {$newHeaders eq {}} {
        return $headers
    }

    foreach {name value} $newHeaders {
        my header $name $value
    }

    return
}

::oo::define ::tanzer::message method headerExists {name} {
    my variable headers

    return [dict exists $headers $name]
}

::oo::define ::tanzer::message method encodingAccepted {encoding} {
    if {![my headerExists Accept-Encoding]} {
        return 0
    }

    set acceptable [my header Accept-Encoding]

    foreach acceptableEncoding [regexp -all -inline {[^,\s]+} $acceptable] {
        switch -nocase -- $encoding $acceptableEncoding {
            return 1
        }
    }

    return 0
}

::oo::define ::tanzer::message method chunked {} {
    my variable chunked

    if {$chunked ne ""} {
        return $chunked
    }

    if {![my headerExists Transfer-Encoding]} {
        return [set chunked 0]
    }

    switch -nocase -- [my header Transfer-Encoding] Chunked {
        return [set chunked 1]
    }

    return [set chunked 0]
}

::oo::define ::tanzer::message method length {} {
    my variable data

    set len [string length $data]

    return [if {$len > 0} {
        list $len
    } elseif {[my headerExists Content-Length]} {
        my header Content-Length
    } else {
        list 0
    }]
}

::oo::define ::tanzer::message method keepalive {} {
    #
    # It's unknown if we want to keep the session alive, so let's let the
    # session handler sort those details out.
    #
    if {![my headerExists Connection]} {
        return 0
    }

    #
    # If there is no Content-Length header, and this is not a chunked message,
    # then we can safely presume that we should say "this message ought to be
    # the last in this session".
    #
    if {![my headerExists Content-Length] && ![my chunked]} {
        return 0
    }

    #
    # Otherwise, if a value does exist, then if it explicitly indicates that
    # the session is to be kept alive, then say "yes".  Otherwise, no.
    #
    set value [my header Connection]

    switch -nocase -- [my header Connection] Keep-Alive {
        return 1
    }

    return 0
}

::oo::define ::tanzer::message method data {} {
    my variable data

    return $data
}

::oo::define ::tanzer::message method buffer {newData} {
    my variable data

    append data $newData

    return
}

::oo::define ::tanzer::message method send {sock} {
    my variable opts headers data

    set tmpHeaders $headers

    if {$opts(request)} {
        dict set tmpHeaders User-Agent \
            "$::tanzer::server::name/$::tanzer::server::version"

        puts -nonewline $sock [format "%s %s %s\r\n" \
            [my method] [my uri] [my version]]
    } elseif {$opts(response)} {
        dict set tmpHeaders Server \
            "$::tanzer::server::name/$::tanzer::server::version"

        set status [my status]

        puts -nonewline $sock [format "%s %d %s\r\n" \
            [my version] $status [::tanzer::response::lookup $status]]
    }

    set len [string length $data]

    if {$len > 0} {
        if {[my chunked]} {
            ::tanzer::error throw [expr {$opts(request)? 400: 500}] \
                "Cannot use chunked transfer encoding in fixed length entities"
        }

        my header Content-Length $len
    }

    foreach {name value} $tmpHeaders {
        puts -nonewline $sock "$name: $value\r\n"
    }

    puts -nonewline $sock "\r\n"

    if {$len > 0} {
        puts -nonewline $sock $data
    }
}
