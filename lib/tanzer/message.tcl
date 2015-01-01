package provide tanzer::message 0.1

##
# @file tanzer/message.tcl
#
# HTTP message object and parser
#

package require TclOO

##
# Global variables specific to parsing HTTP/1.1 messages
#
namespace eval ::tanzer::message {
    ##
    # The maximum length of any HTTP message, including request or response
    # preamble, and headers, is `1MB`.
    #
    variable maxLength 1048576

    ##
    # The default HTTP protocol version assumed is `HTTP/1.1`.
    #
    variable defaultVersion "HTTP/1.1"
}

##
# Determine if the HTTP version string provided in `$version` is supported by
# ::tanzer::message.
#
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

##
# Convert a message field `$name` into a standard representation with
# consistent camel case capitalization.
#
# For example:
#
#     @code
#     ::tanzer::message::field X-FOO-BAR
#
#     ::tanzer::message::field x-foo-bar
#     @endcode
#
# ...All yield `X-Foo-Bar`.
#
proc ::tanzer::message::field {name} {
    set parts [split $name "-"]
    set new   [list]

    foreach part $parts {
        lappend new [string toupper [string tolower $part] 0 0]
    }

    return [join $new "-"]
}

##
# The HTTP message object.
#
::oo::class create ::tanzer::message

##
# Create a new HTTP message.  All arguments in `$args` are passed to the method
# ::tanzer::message::setup verbatim.
#
::oo::define ::tanzer::message constructor {args} {
    my variable opts ready chunked body version \
        newline newlineLength headerLength

    set ready         0
    set chunked       ""
    set body          {}
    set version       $::tanzer::message::defaultVersion
    set headerLength  {}
    set newline       "\r\n"
    set newlineLength 1
    
    array set opts {
        request        0
        response       0
        errorStatus  400
        errorMessage "Invalid Request"
    }

    foreach arg $args {
        switch -- $arg "-request" {
            set opts(request) 1
            break
        } "-response" {
            set opts(response)       1
            set opts(errorStatus)  500
            set opts(errorMessage) "Invalid Response"

            break
        } default {
            error "Invalid argument $arg"
        }
    }
}

##
# Returns true if the current request or response object has been successfully
# parsed by ::tanzer::message::parse.
#
::oo::define ::tanzer::message method ready {} {
    my variable ready

    return $ready
}

##
# Treturns true if the current request or response object has not yet been
# fully parsed by ::tanzer::message::parse.
#
::oo::define ::tanzer::message method incomplete {} {
    my variable ready

    return [expr {$ready == 0}]
}

##
# Parse the HTTP message present in a buffer named `$varName` in the calling
# context.  All headers, request or response data will be parsed and set as
# appropriate in the current message object.
#
::oo::define ::tanzer::message method parse {varName} {
    my variable opts version status ready env headers \
        path uri newline newlineLength headerLength

    #
    # If the message is already parsed, then return true.
    #
    if {$ready} {
        return 1
    }

    upvar 1 $varName buffer

    set bufferLength [string length $buffer]

    #
    # If the buffer is empty, then bail.
    #
    if {$bufferLength == 0} {
        return 0
    }

    #
    # Attempt to locate the header boundary (length) and line break sequence
    # used in the current message.
    #
    if {$headerLength eq {}} {
        set firstnl       [string first "\n" $buffer]
        set prevchar      [string index $buffer [expr {$firstnl - 1}]]
        set newline       [expr {($prevchar eq "\r")? "\r\n": "\n"}]
        set newlineLength [string length $newline]
        set headerEnding  "$newline$newline"
        set headerLength  [expr {
            [string first $headerEnding $buffer] + $newlineLength - 1
        }]
    }

    set bodyStart [expr {$headerLength + $newlineLength + 1}]

    #
    # If we cannot find the end of the headers, then determine if the buffer
    # is too large at this point, and raise an error.  Otherwise, let's try
    # and buffer more data at the next opportunity to read the request and
    # have another go at this.
    #
    if {$headerLength < 0} {
        if {$bufferLength >= $tanzer::message::maxLength} {
            ::tanzer::error throw $opts(errorStatus) "Message too large"
        }

        set headerLength {}

        return 0
    }

    #
    # On the other hand, at this point, we happen to know where the request
    # preamble ends.  Let's try to parse that.
    #
    set preamble    [string range $buffer 0 $headerLength]
    set action      {}
    set headerName  {}
    set headerValue {}

    set valid 0
    set index 0 ;# Current line number
    set start 0 ;# Offset of current line
    set end   [expr {[string first $newline $preamble $start] - 1}]

    while {$end > 0} {
        set line [string range $preamble $start $end]

        if {[regexp -nocase {^(?:HTTP/|)(?:0.9|1.0|1.1)\s+} $line {}]} {
            #
            # Throw an error if we're trying to parse a response status into a
            # non-response object, or if this doesn't happen to be the first line
            # of data provided.
            #
            if {!$opts(response) || $index != 0} {
                ::tanzer::error throw $opts(errorStatus) $opts(errorMessage)
            }

            set responseParts [regexp -all -inline {\S+} $line]
            set partCount     [llength $responseParts]

            if {$partCount < 2} {
                ::tanzer::error throw 500 "Malformed HTTP response"
            }

            lassign $responseParts version status

            set valid 1
        } elseif {[regexp -nocase {^(?:[a-z]+)\s+} $line {}]} {
            #
            # Throw an error if we're trying to parse a request action into a
            # non-request object, or if this doesn't happen to be the first line
            # of data provided.
            #
            if {!$opts(request) || $action ne {} || $index > 0} {
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

            set valid 1
        } elseif {[regexp -nocase {^([a-z][a-z0-9\-_]+):\s+(.*)} $line {} newHeaderName newHeaderValue]} {
            #
            # Set the value of an existing header that was parsed previously, if
            # present.
            #
            if {$headerName ne {} && $headerValue ne {}} {
                my header $headerName $headerValue
            }

            #
            # Then, take note of the header data in the current line.
            #
            set headerName  $newHeaderName
            set headerValue [string trim $newHeaderValue]
        } elseif {[regexp {^\s+(.*)$} $line {} headerValueExtra]} {
            #
            # Look for header value continuation lines.  If there is no previous
            # header line, then that would be quite problematic, indeed.
            #
            if {$headerName eq {}} {
                ::tanzer::error throw $opts(errorStatus) $opts(errorMessage)
            }

            append headerValue " [string trim $headerValueExtra]"
        } else {
            ::tanzer::error throw $opts(errorStatus) $opts(errorMessage)
        }

        set start [expr {$end + $newlineLength + 1}]
        set end   [expr {[string first $newline $preamble $start] - 1}]

        incr index
    }

    #
    # Set remaining headers at the end of the request.
    #
    if {$headerName ne {} && $headerValue ne {}} {
        my header $headerName $headerValue
    }

    #
    # When dealing with response objects in particular...
    #
    if {$opts(response)} {
        #
        # If a status was provided as a headers, then use that instead.
        #
        if {[my headerExists Status]} {
            set status [lindex [my header Status] 0]
        }

        if {$status ne {}} {
            #
            # If our status was declared at some point, then we at least know
            # we're dealing with a valid response.
            #
            set valid 1
        }

        #
        # On the other hand, if our status is >=500, then serve an error page.
        #
        if {$status >= 500} {
            ::tanzer::error throw $status $opts(errorMessage)
        }
    }

    #
    # Die if we've not received a valid message due to either a lacking HTTP
    # request verb or a response status.
    #
    if {!$valid} {
        ::tanzer::error throw $opts(errorStatus) $opts(errorMessage)
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

##
# Return the current message HTTP version string, or, if one was not parsed,
# use the default assumed in ::tanzer::message::defaultVersion.
#
::oo::define ::tanzer::message method version {args} {
    my variable version

    switch -- [llength $args] 0 {
        return $version
    } 1 {
        return [lassign $args version]
    }

    error "Invalid command invocation"
}

##
# Get or set the value of a message header.  If only `$name` is specified, then
# return the value of the header.  If a second argument is specified, then set
# or replace the current value of `$name` its value.
#
::oo::define ::tanzer::message method header {name args} {
    my variable headers

    set name [::tanzer::message::field $name]

    switch -- [llength $args] 0 {
        return [dict get $headers $name]
    } 1 {
        return [dict set headers $name [lindex $args 0]]
    }

    error "Invalid command invocation"
}

##
# Get or set all headers associated with the current message.  If a list of
# key-value pairs is specified in `$newHeaders`, then set each of the headers
# contained therein using ::tanzer::message::header.  Otherwise, return the
# dictionary of headers for the current message.
#
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

##
# Returns true if the header `$name` exists in the current message.
#
::oo::define ::tanzer::message method headerExists {name} {
    my variable headers

    return [dict exists $headers $name]
}

##
# Returns true if an `Accept-Encoding:` header is defined in the current
# message, and the value `$encoding` is one of the lsited accepted encodings
# specified in the message.  Otherwise, returns false.
#
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

##
# Returns true if the current message is presumed to use a chunked transfer
# encoded body, as indicated by the presence of a `Transfer-Encoding:` header
# with a value of `Chunked` (case insensitive).  Otherwise, returns false.
#
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

##
# Append the bytes in `$data` to the current message body.
#
::oo::define ::tanzer::message method buffer {data} {
    my variable body

    append body $data

    return
}

##
# Return any body data buffered for the current message.
#
::oo::define ::tanzer::message method body {} {
    my variable body

    return $body
}

##
# Returns the length of the current message body.  If a message body was
# buffered using ::tanzer::message::buffer, then the total length of the
# message body buffered is returned.  Otherwise, if a `Content-Length:` header
# value is present, return that.  If neither of these conditions are true, then
# return zero to indicate an empty message body.
#
::oo::define ::tanzer::message method length {} {
    my variable body

    set len [string length $body]

    return [if {$len > 0} {
        list $len
    } elseif {[my headerExists Content-Length]} {
        my header Content-Length
    } else {
        list 0
    }]
}

##
# Returns true if there is a `Connection:` header specifying a `keep-alive`
# (case insensitive) value present in the current message.  Or, if there is no
# `Content-Length:` header specified for the current message, then return false
# regardless.  In any other case, return false.
#
::oo::define ::tanzer::message method keepalive {} {
    my variable opts body

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
    if {
         $opts(response)
      && ![my headerExists Content-Length]
      && ![my chunked]
      && [string length $body] == 0
    } {
        return 0
    }

    #
    # Otherwise, if a value does exist, then if it explicitly indicates that
    # the session is to be kept alive, then say "yes".  Otherwise, no.
    #
    switch -nocase -- [my header Connection] Keep-Alive {
        return 1
    }

    return 0
}

##
# Encode and send the current message, headers, body and request or response
# preamble, to the remote end specified by `$sock`.
#
::oo::define ::tanzer::message method send {sock} {
    my variable opts headers body

    set tmpHeaders $headers
    set len        [string length $body]

    if {$len > 0 && [my chunked]} {
        ::tanzer::error throw [expr {$opts(request)? 400: 500}] \
            "Cannot use chunked transfer encoding in fixed length entities"
    }

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

    if {$len > 0} {
        my header Content-Length $len
    }

    foreach {name value} $tmpHeaders {
        puts -nonewline $sock "$name: $value\r\n"
    }

    puts -nonewline $sock "\r\n"

    if {$len > 0} {
        puts -nonewline $sock $body
    }

    flush $sock

    return
}
