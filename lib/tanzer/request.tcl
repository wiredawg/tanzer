package provide tanzer::request 0.0.1
package require tanzer::message
package require tanzer::date
package require tanzer::uri
package require TclOO

namespace eval ::tanzer::request {}

proc ::tanzer::request::hostMatches {host pattern} {
    if {$host eq $pattern} {
        return 1
    }

    set hostParts    [split $host    "."]
    set patternParts [split $pattern "."]

    set h [expr {[llength $hostParts   ] - 1}]
    set p [expr {[llength $patternParts] - 1}]

    while {$h >= 0} {
        set hostPart    [lindex $hostParts    $h]
        set patternPart [lindex $patternParts $p]

        if {$patternPart eq "*"} {
            if {$p != 0} {
                error "Invalid pattern $pattern"
            }

            return 1
        } elseif {$hostPart ne $patternPart} {
            return 0
        } else {
            incr p -1
        }

        incr h -1
    }

    return 1
}

::oo::class create ::tanzer::request {
    superclass ::tanzer::message
}

::oo::define ::tanzer::request constructor {} {
    my variable env headers ready buffer config \
        uri path params timestamp

    set env       [dict create]
    set headers   [dict create]
    set ready     0
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

::oo::define ::tanzer::request method ready {} {
    my variable ready

    return $ready
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

::oo::define ::tanzer::request method parseUri {uriText} {
    my variable env uri path

    set parts [split $uriText "?"]

    dict set env PATH_INFO    [lindex $parts 0]
    dict set env QUERY_STRING [join [lrange $parts 1 end] "?"]

    set uri  [::tanzer::uri::parts [dict get $env REQUEST_URI]]
    set path [::tanzer::uri::parts [dict get $env PATH_INFO]]

    return
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

    #
    # Also bail if the host does not match.
    #
    set host [my host]

    if {$host eq {}} {
        #
        # Force requests without Host: to go through a host route catch-all.
        #
        if {[$route host] ne "*"} {
            return 0
        }
    } elseif {$host ne {}} {
        if {![::tanzer::request::hostMatches $host [$route host]]} {
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

::oo::define ::tanzer::request method method {} {
    my variable env

    return [dict get $env REQUEST_METHOD]
}

::oo::define ::tanzer::request method empty {} {
    my variable headers

    return [expr {[llength $headers] == 0}]
}

::oo::define ::tanzer::request method host {} {
    if {[my headerExists Host]} {
        return [my header Host]
    }

    return {}
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
