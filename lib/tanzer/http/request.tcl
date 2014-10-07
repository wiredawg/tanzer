package provide tanzer::http::request 0.0.1
package require tanzer::request
package require tanzer::error
package require tanzer::uri
package require TclOO

namespace eval ::tanzer::http::request {
    variable proto            "http"
    variable maxRequestLength 1048576
    variable defaultVersion   "HTTP/0.9"
}

proc ::tanzer::http::request::supportedVersion {version} {
    switch $version {
        "HTTP/0.9" -
        "HTTP/1.0" -
        "HTTP/1.1" {
            return 1
        }
    }

    return 0
}

::oo::class create ::tanzer::http::request {
    superclass ::tanzer::request
}

::oo::define ::tanzer::http::request method parse {} {
    my variable buffer ready session \
        env headers path uri

    if {$ready} {
        return 1
    }

    set bufferLength [string length $buffer]
    set headerLength [string first "\r\n\r\n" $buffer]

    #
    # If we cannot find the end of the headers, then determine if the buffer
    # is too large at this point, and raise an error.  Otherwise, let's try
    # and buffer more data at the next opportunity to reqd the request and
    # have another go at this.
    #
    if {$headerLength < 0} {
        if {$bufferLength >= $tanzer::http::request::maxRequestLength} {
            ::tanzer::error throw 400 "Request too large"
        }

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

    set start 0
    set end   [expr {[string first "\r\n" $preamble $start] - 1}]

    while {1} {
        set line [string range $preamble $start $end]

        if {$action eq {}} {
            #
            # Look for the request action, first.
            #
            set action      [regexp -all -inline {\S+} $line]
            set httpMethod  [lindex $action 0]
            set httpUri     [lindex $action 1]
            set httpVersion [lindex $action 2]

            if {$httpVersion eq {}} {
                set httpVersion $::tanzer::http::request::defaultVersion
            }

            if {![::tanzer::http::request::supportedVersion $httpVersion]} {
                ::tanzer::error throw 400 "Bad HTTP version $httpVersion"
            }

            set partCount [llength $action]

            if {$partCount > 3 || $partCount < 2} {
                ::tanzer::error throw 400 "Malformed HTTP action"
            }

            my env REQUEST_METHOD  $httpMethod
            my env REQUEST_URI     $httpUri
            my env SERVER_PROTOCOL $httpVersion
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
                ::tanzer::error throw 400 "Invalid request"
            }

            append headerValue [string trim $headerValueExtra]
        }

        set start [expr {$end + 3}]
        set end   [expr {[string first "\r\n" $preamble $start] - 1}]

        if {$end < 0} {
            break
        }
    }

    #
    # Set remaining headers at the end of the request.
    #
    if {$headerName ne {} && $headerValue ne {}} {
        my header $headerName $headerValue
    }

    #
    # Truncate the header data from the buffer.
    #
    set buffer [string range $buffer $headerLength end]

    #
    # If PATH_INFO or QUERY_STRING do not exist, then infer them from
    # REQUEST_URI.
    #
    my parseUri [my env REQUEST_URI]

    #
    # Set REMOTE_ADDR.
    #
    my env REMOTE_ADDR [lindex [$session get sockaddr] 0]

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
