package provide tanzer::request 0.0.1
package require tanzer::uri
package require TclOO

::oo::class create ::tanzer::request

::oo::define ::tanzer::request constructor {} {
    my variable env headers length ready remaining \
        buffer config uri path params

    set env       [dict create]
    set headers   [dict create]
    set length    0
    set ready     0
    set remaining 0
    set buffer    ""
    set uri       {}
    set path      {}
    set params    {}
}

::oo::define ::tanzer::request method tokenize {data} {
    set tokens         [split $data "\0"]
    set tokenCount     [llength $tokens]
    set tokenLastIndex [expr {$tokenCount - 1}]
    set tokenLast      [lindex $tokens $tokenLastIndex]

    if {$tokenCount % 2 == 0} {
        error "Invalid header format"
    }

    if {[string length $tokenLast] > 0} {
        error "Invalid header format"
    }

    return [lrange $tokens 0 [expr {$tokenLastIndex - 1}]]
}

#
# Return the length of the request headers, including netstring wrapping,
# but not including the size of the body.
#
::oo::define ::tanzer::request method length {} {
    my variable buffer length

    set bufferSize [string length $buffer]

    if {$bufferSize == 0} {
        return 0
    }

    if {$length > 0} {
        return $length
    }

    #
    # We need to check and see if the first bit of the buffer looks like a
    # netstring prefix.  If so, we might actually have read the full headers.
    #
    if {[regexp {^(0|[1-9]\d{0,6}):} $buffer {} length]} {
        return $length
    }

    error "Invalid request header length"
}

::oo::define ::tanzer::request method buffer {data} {
    my variable buffer

    append buffer $data
}

::oo::define ::tanzer::request method validate {} {
    my variable env

    set required {
        SCGI
        CONTENT_LENGTH
        REQUEST_METHOD
        REQUEST_URI
    }

    foreach name $required {
        if {![dict exists $env $name]} {
            error "Invalid request; missing $name header"
        }
    }

    if {[dict get $env SCGI] != 1} {
        error "Invalid request; unknown SCGI version"
    }

    if {[dict get $env CONTENT_LENGTH] < 0} {
        error "Invalid content length"
    }

    return
}

::oo::define ::tanzer::request method store {tokenizedHeaders} {
    my variable env headers params

    #
    # Take the tokenized header data and place the usual CGI headers into $env,
    # and transform the HTTP_ variables to their original HTTP header field names
    # as best as possible.
    #
    foreach {name value} $tokenizedHeaders {
        if {[regexp {^HTTP_(.*)$} $name {} nameSuffix]} {
            set nameParts [list]

            foreach namePart [split $nameSuffix _] {
                lappend nameParts [string toupper [string tolower $namePart] 0 0]
            }

            dict set headers [join $nameParts -] $value
        } else {
            dict set env $name $value
        }
    }

    #
    # Store CONTENT_LENGTH as an HTTP header named Content-Length, too.
    #
    set contentLength [dict get $env CONTENT_LENGTH]

    if {$contentLength > 0} {
        dict set headers Content-Length $contentLength
    }

    #
    # Parse the parameters passed in QUERY_STRING, if available.
    #
    if {[dict exists $env QUERY_STRING]} {
        foreach pair [split [dict get $env QUERY_STRING] "&"] {
            #
            # Split only once, in case a value contains an equals for whatever
            # perverse reason.
            #
            if {[regexp {^(.*)=(.*)$} $pair {} name value]} {
                dict set params \
                    [::tanzer::uri::decode $name] [::tanzer::uri::decode $value]
            }
        }
    }

    return
}

::oo::define ::tanzer::request method incomplete {} {
    my variable ready

    return [expr {$ready == 0}]
}

::oo::define ::tanzer::request method remaining {args} {
    my variable ready remaining

    if {[llength $args] == 1} {
        if {!$ready} {
            error "Request not ready"
        }

        incr remaining [lindex $args 0]
    }

    return $remaining
}

::oo::define ::tanzer::request method parse {} {
    my variable buffer ready env remaining \
        path uri

    set length [my length]

    if {$length == 0} {
        return 0
    }

    #
    # If the buffer contains at least the full header netstring with the
    # size indicated, as well as the netstring wrappers itself, then do a
    # quick validation to ensure a netstring format.  Then, extract the
    # header names and values.
    #
    set bufferSize [string length $buffer]

    set bufferSizeExpected [expr {
          2
        + $length
        + [string length $length]}]

    if {$bufferSize < $bufferSizeExpected} {
        return 0
    }

    set endIndex [expr {$bufferSizeExpected - 1}]

    if {[string index $buffer $endIndex] ne ","} {
        error "Invalid request format"
    }

    set startIndex [expr {
          1
        + [string length $length]}]

    #
    # Capture the header data from within the body of the netstring.
    #
    set headerData [string range $buffer $startIndex [expr {$endIndex - 1}]]

    #
    # Tokenize and store the header data.
    #
    my store [my tokenize $headerData]

    #
    # Ensure the request was fully formed as is required by the SCGI spec.
    #
    my validate

    #
    # Truncate the header data from the buffer.
    #
    set buffer [string range $buffer [expr {$endIndex + 1}] end]

    #
    # Set the number of remaining bytes to the CONTENT_LENGTH header value.
    #
    set remaining [dict get $env CONTENT_LENGTH]

    #
    # If PATH_INFO or QUERY_STRING do not exist, then infer them from
    # REQUEST_URI.
    #
    set parts [split [dict get $env REQUEST_URI] ?]

    if {![dict exists $env PATH_INFO]} {
        dict set env PATH_INFO [lindex $parts 0]
    }

    if {![dict exists $env QUERY_STRING]} {
        dict set env QUERY_STRING [join [lrange $parts 1 end] ?]
    }

    #
    # Store path information in the current object.
    #
    set uri  [::tanzer::uri::parts [dict get $env REQUEST_URI]]
    set path [::tanzer::uri::parts [dict get $env PATH_INFO]]

    #
    # Finally, update the ready flag to indicate that the request is now
    # usable to the session handler.
    #
    set ready 1

    return 1
}

::oo::define ::tanzer::request method uri {} {
    my variable uri

    return $uri
}

::oo::define ::tanzer::request method path {} {
    my variable path

    return $path
}

::oo::define ::tanzer::request method matches {route} {
    my variable params path

    set method [$route method]

    #
    # Bail early if the route method does not match.
    #
    if {$method ne "*"} {
        set foundMethod 0

        foreach methodCandidate $method {
            if {$method eq $methodCandidate} {
                set foundMethod 1
            }
        }

        if {!$foundMethod} {
            return 0
        }
    }

    set pattern    [$route pattern]
    set partsLen   [llength $pattern]
    set requestLen [llength $path]
    set _params    [list]

    set wildcard 0

    for {set i 0} {$i < $partsLen} {incr i} {
        set partRoute   [lindex $pattern $i]
        set partRequest [lindex $path    $i]

        #
        # If there is no request part in the position corresponding to the
        # position of the route part, then the route does not match.
        #
        if {$i >= $requestLen} {
            return 0
        }

        #
        # If the current route part is a wildcard, then everything at this
        # position, and thereafter, in the request, shall match.
        #
        if {$partRoute eq "*"} {
            #
            # On the other hand, if the wildcard is not at the end of the
            # route, then that's a problem.
            #
            if {$i != $partsLen - 1} {
                return 0
            }

            set wildcard 1

            break
        }

        #
        # If the current route part is a parameter marker, then take the
        # URL decoded value from the corresponding request part.
        #
        if {[regexp {^:(.*)$} $partRoute {} key]} {
            dict set _params \
                [::tanzer::uri::decode $key] [::tanzer::uri::decode $partRequest]
        } elseif {$partRoute ne $partRequest} {
            return 0
        }
    }

    #
    # If we did not find a wildcard route part at the end, then the route does
    # not match.
    #
    if {!$wildcard && $partsLen != [llength $path]} {
        return 0
    }

    #
    # If we've found any parameters, then merge them into the request
    # parameters dictionary.
    #
    if {[llength $_params] > 0} {
        dict set params {*}$_params
    }

    return 1
}

::oo::define ::tanzer::request method param {args} {
    my variable params

    if {[llength $args] == 1} {
        return [dict get $params [lindex $args 0]]
    }

    if {[llength $args] == 2} {
        return [dict set params {*}$args]
    }

    error "Invalid command invocation"
}

::oo::define ::tanzer::request method params {} {
    my variable params

    return $params
}

::oo::define ::tanzer::request method data {} {
    my variable buffer

    return $buffer
}

::oo::define ::tanzer::request method env {args} {
    my variable env

    if {[llength $args] == 1} {
        return [dict get $env [lindex $args 0]]
    }

    if {[llength $args] == 2} {
        return [dict set env {*}$args]
    }

    return $env
}

::oo::define ::tanzer::request method headers {} {
    my variable headers

    return $headers
}

::oo::define ::tanzer::request method header {key} {
    my variable headers

    return [dict get $headers $key]
}

::oo::define ::tanzer::request method headerExists {key} {
    my variable headers

    return [dict exists $headers $key]
}

::oo::define ::tanzer::request method method {} {
    my variable env

    return [dict get $env REQUEST_METHOD]
}

::oo::define ::tanzer::request method empty {} {
    my variable headers

    return [expr {[llength $headers] == 0}]
}
