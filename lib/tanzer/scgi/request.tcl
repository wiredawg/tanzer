package provide tanzer::scgi::request 0.0.1
package require tanzer::request
package require tanzer::error
package require tanzer::uri
package require TclOO

namespace eval ::tanzer::scgi::request {
    variable proto "scgi"
}

::oo::class create ::tanzer::scgi::request {
    superclass ::tanzer::request
}

::oo::define ::tanzer::scgi::request constructor {} {
    my variable length remaining

    next

    set length    0
    set remaining 0
}

::oo::define ::tanzer::scgi::request method tokenize {data} {
    set tokens         [split $data "\0"]
    set tokenCount     [llength $tokens]
    set tokenLastIndex [expr {$tokenCount - 1}]
    set tokenLast      [lindex $tokens $tokenLastIndex]

    if {$tokenCount % 2 == 0} {
        ::tanzer::error throw 400 "Invalid header format"
    }

    if {[string length $tokenLast] > 0} {
        ::tanzer::error throw 400 "Invalid header format"
    }

    return [lrange $tokens 0 [expr {$tokenLastIndex - 1}]]
}

#
# Return the length of the request headers, including netstring wrapping,
# but not including the size of the body.
#
::oo::define ::tanzer::scgi::request method length {} {
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

    ::tanzer::error throw 400 "Invalid request header length"
}

::oo::define ::tanzer::scgi::request method validate {} {
    my variable env

    set required {
        SCGI
        CONTENT_LENGTH
        REQUEST_METHOD
        REQUEST_URI
    }

    foreach name $required {
        if {![dict exists $env $name]} {
            ::tanzer::error throw 400 "Invalid request; missing $name header"
        }
    }

    if {[dict get $env SCGI] != 1} {
        ::tanzer::error throw 400 "Invalid request; unknown SCGI version"
    }

    if {[dict get $env CONTENT_LENGTH] < 0} {
        ::tanzer::error throw 400 "Invalid content length"
    }

    return
}

::oo::define ::tanzer::scgi::request method store {tokenizedHeaders} {
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

::oo::define ::tanzer::scgi::request method remaining {args} {
    my variable ready remaining

    if {[llength $args] == 1} {
        if {!$ready} {
            ::tanzer::error throw 400 "Request not ready"
        }

        incr remaining [lindex $args 0]
    }

    return $remaining
}

::oo::define ::tanzer::scgi::request method parse {} {
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
        ::tanzer::error throw 400 "Invalid request format"
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
