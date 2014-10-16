package provide tanzer::message 0.0.1
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
    my variable opts ready

    set ready 0
    
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

::oo::define ::tanzer::message method parse {buffer} {
    my variable opts version status ready env headers \
        path uri headerLength

    if {$ready} {
        return 1
    }

    set bufferLength [string length $buffer]
    set headerLength [string first "$opts(newline)$opts(newline)" $buffer]

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

    while {1} {
        set line [string range $preamble $start $end]

        if {[regexp -nocase {^HTTP/(?:0.9|1.0|1.1)\s+} $line {}]} {
            if {!$opts(response) || $index != 0} {
                ::tanzer::error throw $opts(errorStatus) $opts(errorMessage)
            }

            set responseParts [regexp -all -inline {\S+} $line]
            set partCount     [llength $responseParts]

            if {$partCount > 3 || $partCount < 2} {
                ::tanzer::error throw 500 "Malformed HTTP response"
            }

            set version [$lindex $responseParts 0]
            set status  [$lindex $responseParts 1]
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

            set httpMethod  [lindex $action 0]
            set httpUri     [lindex $action 1]
            set httpVersion [lindex $action 2]

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

        if {$end < 0} {
            break
        }

        incr index
    }

    #
    # Set remaining headers at the end of the request.
    #
    if {$headerName ne {} && $headerValue ne {}} {
        my header $headerName $headerValue
    }

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

::oo::define ::tanzer::message method version {args} {
    my variable version

    if {[llength $args] == 1} {
        set version [lindex $args 0]

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

::oo::define ::tanzer::message method header {name args} {
    my variable headers

    if {[llength $args] == 0} {
        return [dict get $headers [::tanzer::message::field $name]]
    } elseif {[llength $args] == 1} {
        set name  [::tanzer::message::field $name]
        set value [lindex $args 0]

        dict set headers $name $value

        return [list $name $value]
    }

    error "Invalid command invocation"
}

::oo::define ::tanzer::message method headers {args} {
    my variable headers

    if {[llength $args] == 0} {
        return $headers
    }

    if {[llength $args] == 1} {
        foreach {name value} [lindex $args 0] {
            my header $name $value
        }

        return $headers
    }

    if {{llength $args} % 2 == 0} {
        foreach {name value} $args {
            my header $name $value
        }

        return $headers
    }

    error "Invalid arguments"
}

::oo::define ::tanzer::message method headerExists {args} {
    my variable headers

    foreach key $args {
        if {[dict exists $headers $key]} {
            return 1
        }
    }

    return 0
}

::oo::define ::tanzer::message method length {} {
    if {[my headerExists Content-Length]} {
        return [my header Content-Length]
    }

    return 0
}

::oo::define ::tanzer::message method keepalive {} {
    if {[my headerExists Connection]} {
        set value [my header Connection]

        switch -nocase -- [my header Connection] Keep-Alive {
            return 1
        }
    }

    return 0
}
