package provide tanzer::scgi::request 0.1

##
# @file tanzer/scgi/request.tcl
#
# Facility for supporting inbound SCGI reuqests
#

package require tanzer::request
package require tanzer::error
package require tanzer::uri
package require TclOO

namespace eval ::tanzer::scgi::request {
    variable proto     "scgi"
    variable keepalive 1
}

##
# The facilities for providing SCGI services.  Incrementally parses an inbound
# SCGI request, and decodes all request parameters into the appropriate HTTP
# message header values.  Not meant to be used directly; but rather, SCGI
# service can be achieved in ::tanzer::server by choosing `proto` configuration
# value `scgi` rather than the default `http`.
#
::oo::class create ::tanzer::scgi::request {
    superclass ::tanzer::request
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

    return
}

::oo::define ::tanzer::scgi::request method parse {varName} {
    my variable ready env path uri \
        headerLength

    upvar $varName buffer

    set bufferSize [string length $buffer]

    #
    # If the buffer is empty, then bail.
    #
    if {$bufferSize == 0} {
        return 0
    }

    #
    # We need to check and see if the first bit of the buffer looks like a
    # netstring prefix.  If so, we might actually have read the full headers.
    #
    if {$headerLength eq ""} {
        if {![regexp {^(0|[1-9]\d{0,6}):} $buffer {} headerLength]} {
            ::tanzer::error throw 400 "Invalid request header length"
        }
    }

    #
    # If the buffer contains at least the full header netstring with the
    # size indicated, as well as the netstring wrappers itself, then do a
    # quick validation to ensure a netstring format.  Then, extract the
    # header names and values.
    #
    set bufferSizeExpected [expr {
          2
        + $headerLength
        + [string length $headerLength]}]

    if {$bufferSize < $bufferSizeExpected} {
        return 0
    }

    set endIndex [expr {$bufferSizeExpected - 1}]

    if {[string index $buffer $endIndex] ne ","} {
        ::tanzer::error throw 400 "Invalid request format"
    }

    set startIndex [expr {
          1
        + [string length $headerLength]}]

    #
    # Bump the headerLength size up to include its netstring wrapper, as we
    # will want to consume the entire header, netstring outer shell and all.
    #
    incr headerLength [expr {2 + [string length $headerLength]}]

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
    # Set the number of remaining bytes to the CONTENT_LENGTH header value,
    # and determine if the request is too long or short.
    #
    set remaining [expr {
        [string length $buffer] - $headerLength - [my length]}]

    if {$remaining < 0} {
        ::tanzer::error throw 400 "Request body too long"
    } elseif {$remaining > 0} {
        ::tanzer::error throw 400 "Request body too short"
    }

    #
    # Parse the URI information passed from REQUEST_URI.
    #
    my uri [dict get $env REQUEST_URI]

    #
    # Finally, update the ready flag to indicate that the request is now
    # usable to the session handler.
    #
    set ready 1

    return 1
}
