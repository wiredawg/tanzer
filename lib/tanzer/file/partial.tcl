package provide tanzer::file::partial 0.1
package require tanzer::file::fragment
package require tanzer::file
package require tanzer::error
package require tanzer::response
package require TclOO

::oo::class create ::tanzer::file::partial {
    superclass ::tanzer::file
}

::oo::define ::tanzer::file::partial constructor {newPath newSt newConfig request} {
    my variable fragments st multipart mismatched

    next $newPath $newSt $newConfig

    set mismatched [expr {![my rangeMatch $request]}]
    set fragments  {}

    if {$mismatched} {
        set fragments {}
        set multipart 0
    } else {
        set fragments [::tanzer::file::fragment::parseRangeRequest \
            $request $st(size) [my mimeType]]

        set multipart [expr {[llength $fragments] > 1}]
    }
}

::oo::define ::tanzer::file::partial destructor {
    my variable fragments

    next

    if {[llength $fragments] == 0} {
        return
    }

    foreach fragment $fragments {
        $fragment destroy
    }
}

::oo::define ::tanzer::file::partial method fragment {args} {
    my variable fragments

    array set opts {
        next 0
    }

    if {[llength $fragments] == 0} {
        return {}
    }

    foreach arg $args {
        switch $arg {
            -next {
                set opts(next) 1
            }

            default {
                error "Invalid option $arg"
            }
        }
    }

    set fragment [lindex $fragments 0]

    if {$opts(next)} {
        $fragment destroy

        return [lindex [set fragments [lreplace $fragments 0 0]] 0]
    }

    return $fragment
}

::oo::define ::tanzer::file::partial method multipart {} {
    my variable multipart

    return $multipart
}

::oo::define ::tanzer::file::partial method final {} {
    my variable fragments

    return [expr {[llength $fragments] == 1}]
}

::oo::define ::tanzer::file::partial method rangeMatch {request} {
    if {![$request headerExists If-Range]} {
        return 1
    }

    set value [$request header If-Range]

    return [expr {[my entityMatches $value] || ![my entityNewerThan $value]}]
}

::oo::define ::tanzer::file::partial method mismatched {} {
    my variable mismatched

    return $mismatched
}

::oo::define ::tanzer::file::partial method stream {event session} {
    my variable config fh fragments mismatched

    #
    # If any present If-Range: precondition failed, then we need to serve the
    # whole entity body.
    #
    if {$mismatched} {
        return [next $event $session]
    }

    set fragment [my fragment]

    #
    # If there are no more fragments to be read, then finish the request.
    #
    if {$fragment eq {}} {
        $session nextRequest
        my destroy
        return
    }

    #
    # If we are fulfilling a multi-fragment partial request, then check and
    # see if we have sent a fragment header for the current fragment.  If not,
    # send the header.
    #
    if {[my multipart] && [$fragment firstChunk]} {
        $session write [$fragment header]
    }

    set sock [$session sock]

    foreach event {readable writable} {
        chan event $sock $event {}
    }

    seek $fh [$fragment offset]

    chan copy $fh $sock -size [$fragment size] -command [list apply {
        {self session written args} {
            #
            # If we were not able to pipe any data from the input file to the output
            # socket, then finish the request.
            #
            if {[llength $args] > 0} {
                $session error [lindex $args 0]

                return
            }

            #
            # Since we are done with the current fragment, then move on to the
            # next.
            #
            if {[$self final]} {
                $session write "\r\n--$::tanzer::file::fragment::boundary--\r\n"
            }

            #
            # Move on to the next partial file fragment.
            #
            $self fragment -next

            #
            # Pass control of the socket back to the session handler.
            #
            $session reset write
        }
    } [self] $session]

    return
}

::oo::define ::tanzer::file::partial method contentLength {} {
    my variable fragments mismatched

    #
    # If the request for which this file was opened fails an If-Range:
    # precondition, then use the content length reported by ::tanzer::file
    # instead.
    #
    if {$mismatched} {
        return [next]
    }

    if {![my multipart]} {
        set fragment [my fragment]

        if {$fragment eq {}} {
            ::tanzer::error throw 400 "No request fragments found"
        }

        return [$fragment size]
    }

    set length [string length $::tanzer::file::fragment::endBoundary]

    foreach fragment $fragments {
        incr length [$fragment size -total]
    }

    return $length
}

::oo::define ::tanzer::file::partial method headers {} {
    my variable mismatched

    set headers [next]

    #
    # If the request for which this file was opened fails an If-Range:
    # precondition, then do not override the headers set in ::tanzer::file.
    #
    if {$mismatched} {
        return $headers
    }

    dict set headers Content-Length [my contentLength]

    if {[my multipart]} {
        dict set headers Content-Type \
            "multipart/byteranges; boundary=$::tanzer::file::fragment::boundary"
    } else {
        dict set headers Content-Type  [my mimeType]
        dict set headers Content-Range [[my fragment] contentRange]
    }

    return $headers
}
