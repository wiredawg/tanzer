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
    my variable buffer ready env remaining \
        path uri

    if {$ready} {
        return 1
    }

    set bufferLength [string length $buffer]
    set headerLength [string first $buffer "\r\n\r\n"]

    puts "Got header length $headerLength"

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

    foreach line [split $preamble "\r\n"] {
        #
        # Look for the request action, first.
        #
        if {$action eq {}} {
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

            continue
        }

        #
        # Look for new headers.
        #
        if {[regexp -nocase {^([a-z][a-z0-9\-]+):\S+(.*)} $line {} $headerName $headerValue]} {
            set headerValue [string trim $headerValue]

            continue
        }

        #
        # Look for header value continuation lines.
        #
        if {[regexp {^\s+(.*)$} $line {} headerValueExtra]} {
            if {$headerName eq {}} {
                ::tanzer::error throw 400 "Invalid header"
            }

            append headerValue [string trim $headerValueExtra]

            continue
        }

        ::tanzer::error throw 400 "Malformed request"
    }

    puts "Now we're here"

    #
    # Truncate the header data from the buffer.
    #
    set buffer [string range $buffer $headerLength end]

    #
    # If PATH_INFO or QUERY_STRING do not exist, then infer them from
    # REQUEST_URI.
    #
    my parseUri [dict get $env REQUEST_URI]

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
