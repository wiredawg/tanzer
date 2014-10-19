package provide tanzer::request 0.0.1
package require tanzer::message
package require tanzer::date
package require tanzer::uri
package require TclOO

namespace eval ::tanzer::request {}

::oo::class create ::tanzer::request {
    superclass ::tanzer::message
}

::oo::define ::tanzer::request constructor {newSession} {
    my variable session env headers buffer config \
        uri path params rewritten timestamp headerLength

    next -newline "\r\n" \
         -request

    set session      $newSession
    set env          [dict create]
    set headers      [dict create]
    set uri          {}
    set path         {}
    set params       {}
    set rewritten    0
    set headerLength 0
    set timestamp    [::tanzer::date::rfc2616 [clock seconds]]
}

::oo::define ::tanzer::request method uri {{newUri ""}} {
    my variable uri path

    if {$newUri eq ""} {
        return $uri
    }

    set uri      $newUri
    set uriParts [split $uri "?"]
    set path     [::tanzer::uri::parts [lindex $uriParts 0]]
    set query    [join [lrange $uriParts 1 end] "?"]

    foreach pair [split $query "&"] {
        #
        # Split only once, in case a value contains an equals for whatever
        # perverse reason.
        #
        if {[regexp {^(.*)=(.*)$} $pair {} name value]} {
            my param \
                [::tanzer::uri::decode $name] [::tanzer::uri::decode $value]
        }
    }

    my env REQUEST_URI  $uri
    my env QUERY_STRING $query

    return
}

::oo::define ::tanzer::request method rewrite {re newFormat} {
    my variable uri rewritten

    if {$rewritten} {
        return 1
    }

    if {$uri eq {}} {
        error "Cannot rewrite URI on request that has not been matched"
    }

    set matches [regexp -inline $re $uri]

    if {[llength $matches] == 0} {
        return 0
    }

    my uri [format $newFormat {*}[lrange $matches 1 end]]

    return 1
}

::oo::define ::tanzer::request method path {} {
    my variable path

    return $path
}

::oo::define ::tanzer::request method hostMatches {route} {
    set host    [my host]
    set pattern [$route host]

    if {$host eq {}} {
        #
        # Force requests without Host: to go through a host route catch-all.
        #
        if {$pattern ne "*"} {
            return 0
        }
    } elseif {$host eq $pattern} {
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

    #
    # If the host pattern contained no wildcard, and differs in number of
    # components, then fail.
    #
    if {$h != $p} {
        return 0
    }

    return 1
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
    if {![my hostMatches $route]} {
        return 0
    }

    set pattern    [$route pattern]
    set partsLen   [llength $pattern]
    set requestLen [llength $path]
    set matching   [list]
    set pathInfo   [list]
    set newParams    [list]

    set wildcard 0

    for {set i 0} {$i < $partsLen} {incr i} {
        set partRoute   [lindex $pattern $i]
        set partRequest [lindex $path    $i]

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
        } elseif {$i >= $requestLen} {
            #
            # If there is no request part in the position corresponding to the
            # position of the route part, and the current route part is not
            # a glob, then the route does not match.
            #
            return 0
        }

        #
        # If the current route part is a parameter marker, then take the
        # URL decoded value from the corresponding request part.
        #
        if {[regexp {^:(.*)$} $partRoute {} key]} {
            my param $key $partRequest
        } elseif {$partRoute ne $partRequest} {
            return 0
        }

        lappend matching $partRequest
    }

    if {$wildcard} {
        for {#} {$i < $requestLen} {incr i} {
            set part [lindex $path $i]

            if {$part eq {}} {
                continue
            }

            if {[llength $pathInfo] == 0} {
                lappend pathInfo {}
            }

            lappend pathInfo $part
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
    # Set PATH_INFO, now that we have enough data to do so.
    #
    my env PATH_INFO [::tanzer::uri::text $pathInfo]

    #
    # If we've found any parameters, then merge them into the request
    # parameters dictionary.
    #
    if {[llength $newParams] > 0} {
        my params $newParams
    }

    return 1
}

::oo::define ::tanzer::request method param {name {value ""}} {
    my variable params

    if {$value ne ""} {
        dict set params $name $value

        return
    }

    return [dict get $params $name]
}

::oo::define ::tanzer::request method params {{newParams {}}} {
    my variable params

    if {$newParams ne {}} {
        set params [dict create {*}$newParams]

        return
    }

    return $params
}

::oo::define ::tanzer::request method env {{name ""} {value ""}} {
    my variable env

    if {$value ne ""} {
        dict set env $name $value

        return
    } elseif {$name ne ""} {
        return [if {[dict exists $env $name]} {
            dict get $env $name
        } else {
            list ""
        }]
    }

    return $env
}

::oo::define ::tanzer::request method method {} {
    my variable env

    if {[dict exists $env REQUEST_METHOD]} {
        return [dict get $env REQUEST_METHOD]
    }

    return "-"
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

::oo::define ::tanzer::request method client {} {
    my variable env

    if {[dict exists $env REMOTE_ADDR]} {
        return [dict get $env REMOTE_ADDR]
    }

    return "-"
}

::oo::define ::tanzer::request method proto {} {
    my variable env

    if {[dict exists $env SERVER_PROTOCOL]} {
        return [dict get $env SERVER_PROTOCOL]
    }

    return "-"
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
