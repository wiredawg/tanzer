package provide tanzer::request 0.0.1
package require tanzer::date
package require tanzer::uri
package require TclOO

::oo::class create ::tanzer::request

::oo::define ::tanzer::request constructor {} {
    my variable env headers length ready remaining \
        buffer config uri path params timestamp

    set env       [dict create]
    set headers   [dict create]
    set length    0
    set ready     0
    set remaining 0
    set buffer    ""
    set uri       {}
    set path      {}
    set params    {}
    set timestamp [::tanzer::date::rfc2616 [clock seconds]]
}

::oo::define ::tanzer::request method buffer {data} {
    my variable buffer

    append buffer $data
}

::oo::define ::tanzer::request method validate {} {
    error "Not implemented"
}

::oo::define ::tanzer::request method incomplete {} {
    my variable ready

    return [expr {$ready == 0}]
}

::oo::define ::tanzer::request method parse {} {
    error "Not implemented"
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

::oo::define ::tanzer::request method referer {} {
    if {[my headerExists Referer]} {
        return [my header Referer]
    }

    return "-"
}

::oo::define ::tanzer::request method agent {} {
    if {[my headerExists User-Agent]} {
        return [my header User-Agent]
    }

    return "(unknown)"
}

::oo::define ::tanzer::request method timestamp {} {
    my variable timestamp

    return $timestamp
}
