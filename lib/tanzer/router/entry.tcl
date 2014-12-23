package provide tanzer::router::entry 0.1

##
# @file tanzer/router/entry.tcl
#
# The request handler router entry object
#

package require tanzer::error
package require tanzer::uri
package require TclOO

##
# The HTTP request handler route specification object, wherein the HTTP request
# method regular expression, path glob pattern, host regular expression, and
# request handler script are kept; routes are held by ::tanzer::server in a
# flat list, and compared by ::tanzer::server in order until it finds a route
# object that ::tanzer::request deems matching.
#
::oo::class create ::tanzer::router::entry

##
# Create a new route object with the specified case-insensitive HTTP method 
# regular expression in `$newMethod`, request path pattern in `$newPattern`,
# `Host:` header match pattern in `$newHost`, and request handler in
# `$newScript`.
#
::oo::define ::tanzer::router::entry constructor {newMethod newPattern newHost newScript} {
    my variable method pattern host script

    if {[catch {regexp $newHost ""}]} {
        error "Invalid host pattern $newHost"
    }

    set method  $newMethod
    set host    $newHost
    set script  $newScript
    set pattern [::tanzer::uri::parts $newPattern]
}

::oo::define ::tanzer::router::entry destructor {
    my variable pattern

    $pattern destroy
}

##
# Returns the host matching regular expression for the current route.
#
::oo::define ::tanzer::router::entry method host {} {
    my variable host

    return $host
}

##
# Returns the method routing regular expression for the current route.
#
::oo::define ::tanzer::router::entry method method {} {
    my variable method

    return $method
}


##
# Returns the request path routing pattern for the current route.
#
::oo::define ::tanzer::router::entry method pattern {} {
    my variable pattern

    return $pattern
}

##
# Returns the request handler callback script for the current route.
#
::oo::define ::tanzer::router::entry method script {} {
    my variable script

    return $script
}

##
# Given an ::tanzer::uri object in `$path`, return the relative path string
# matched by the ending glob.
#
::oo::define tanzer::router::entry method relative {path} {
    my variable pattern

    set relativeParts [list]

    set pathLen [llength $path]

    if {$pathLen < [llength $pattern]} {
        ::tanzer::error throw 416 "Request path is shorter than route path"
    }

    set wildcard 0

    for {set i 0} {$i < $pathLen} {incr i} {
        set partRoute [lindex $pattern $i]
        set partPath  [lindex $path    $i]

        if {$partRoute eq "*"} {
            set wildcard 1
        }

        if {$wildcard} {
            lappend relativeParts $partPath
        } elseif {$partRoute ne $partPath} {
            ::tanzer::error throw 416 error "Path does not match route"
        }
    }

    return $relativeParts
}

##
# Returns true if the ::tanzer::router::entry object specified by `$route`
# matches the current request.  Furthermore, upon a successful match, any
# positional parameters matching the `:param` format are stored in the current
# request.  The following match criteria are considered, in order:
#
# 1. If the regular expression supplied for the HTTP method of the route does
#    not match that of `$request`, then return false.
#
# 2. If the regular expression supplied for the HTTP host of the route does not
#    match the HTTP `Host:` header of `$request`, then return false.
#
# 3. If the glob pattern supplied for the HTTP reuqest path of the route does
#    not match the path of `$request`, then return false.
#
# As an additional side effect, any path components matching at and beyond the
# point of a route path glob are stored as a string in the request environment
# variable `PATH_INFO`, in the same fashion as CGI/1.1.
#
::oo::define ::tanzer::router::entry method matches {request} {
    my variable method pattern host

    set path [$request path]

    #
    # Bail early if the route method does not match.
    #
    if {![regexp -nocase "^${method}\$" [$request method]]} {
        return 0
    }

    #
    # Also bail if the host does not match the pattern regex.
    #
    if {![regexp -nocase "^$host\$" [$request host]]} {
        return 0
    }

    set partsLen   [llength $pattern]
    set requestLen [llength $path]
    set matching   [list]
    set pathInfo   [list]
    set newParams  [list]

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
            $request param $key $partRequest
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
    $request env PATH_INFO [::tanzer::uri::text $pathInfo]

    #
    # If we've found any parameters, then merge them into the request
    # parameters dictionary.
    #
    if {[llength $newParams] > 0} {
        $request params $newParams
    }

    return 1
}
