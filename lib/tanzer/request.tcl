package provide tanzer::request 0.1
package require tanzer::message
package require tanzer::date
package require tanzer::uri
package require TclOO

##
# The HTTP/1.1 request object.
#
::oo::class create ::tanzer::request {
    superclass ::tanzer::message
}

##
# Create a request object attached to the session specified in `$newSession`.
#
::oo::define ::tanzer::request constructor {newSession} {
    my variable session env headers buffer uri path \
        params rewritten timestamp headerLength

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

##
# Parse the URI passed in `$newUri` for the URL-decoded path component, and the
# query string.  These individual components will be parsed and URL decoded as
# appropriate.  `$newUri` will be saved literally in the current request for
# future reference.
#
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

##
# Match the URI stored in a previous invocation of ::tanezr::requst::uri with
# the regular expression in `$re`, and replace it with the newly formatted
# string created from the `[format]` string in `$newFormat`, with the values of
# subexpression matches given for positional format arguments.
#
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

##
# Return the URL decoded path component of the URI previously passed to the
# current request by ::tanzer::request::uri.
#
::oo::define ::tanzer::request method path {} {
    my variable path

    return $path
}

##
# Returns true if the ::tanzer::route object specified by `$route` matches the
# current request.  Furthermore, upon a successful match, any positional
# parameters matching the `:param` format are stored in the current request.
# The following match criteria are considered, in order:
#
# 1. If the regular expression supplied for the HTTP method of `$route` does
#    not match that of the current request, then return false.
#
# 2. If the regular expression supplied for the HTTP host of `$route` does not
#    match the HTTP `Host:` header of the current request, then return false.
#
# 3. If the glob pattern supplied for the HTTP reuqest path of `$route` does
#    not match the current request path, then return false.
#
# As an additional side effect, any path components matching at and beyond the
# point of a route path glob are stored as a string in the request environment
# variable `PATH_INFO`, in the same fashion as CGI/1.1.
#
::oo::define ::tanzer::request method matches {route} {
    my variable params path

    set method [$route method]

    #
    # Bail early if the route method does not match.
    #
    if {![regexp -nocase "^${method}\$" [my method]]} {
        return 0
    }

    #
    # Also bail if the host does not match the pattern regex.
    #
    if {![regexp -nocase "^[$route host]\$" [my host]]} {
        return 0
    }

    set pattern    [$route pattern]
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

##
# Return the value of the parameter called `$name`, or if `$value` is also
# specified, set the value of `$name` to `$value`.
#
::oo::define ::tanzer::request method param {name {value ""}} {
    my variable params

    if {$value ne ""} {
        dict set params $name $value

        return
    }

    return [dict get $params $name]
}

##
# Return a key-value pair list of parameters parsed by a prior call to
# ::tanzer::request::match.  If `$newParams` is specified, then replace all
# current parameters with the values therein.
#
::oo::define ::tanzer::request method params {{newParams {}}} {
    my variable params

    if {$newParams ne {}} {
        set params [dict create {*}$newParams]

        return
    }

    return $params
}

##
# Return all the CGI/1.1 environment variables set for the current request as a
# list of key-value pairs.  If `$name` is supplied, then return only the value
# of that variable, if it exists.  If `$value` is also supplied, then set the
# environment variable `$name` with that value.
#
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

##
# Return the HTTP method verb of the current request, or `-` if one was not
# parsed nor specified previously.
#
::oo::define ::tanzer::request method method {} {
    my variable env

    if {[dict exists $env REQUEST_METHOD]} {
        return [dict get $env REQUEST_METHOD]
    }

    return "-"
}

##
# Returns true if no headers are present for the current request.
#
::oo::define ::tanzer::request method empty {} {
    my variable headers

    return [expr {[llength $headers] == 0}]
}

##
# Returns the value of the `Host:` header for the current request, or an empty
# string if one is not present.
#
::oo::define ::tanzer::request method host {} {
    if {[my headerExists Host]} {
        return [my header Host]
    }

    return {}
}

##
# Returns the value of the `REMOTE_ADDR` environment variable set for the
# current request, or `-` if no such variable is present.
#
::oo::define ::tanzer::request method client {} {
    my variable env

    if {[dict exists $env REMOTE_ADDR]} {
        return [dict get $env REMOTE_ADDR]
    }

    return "-"
}

##
# Returns the value of the `SERVER_PROTOCOL` environment variable set for the
# current request, or `-` if no such variable is present.
#
::oo::define ::tanzer::request method proto {} {
    my variable env

    if {[dict exists $env SERVER_PROTOCOL]} {
        return [dict get $env SERVER_PROTOCOL]
    }

    return "-"
}

##
# Returns the value of the `Referer:` header of the current request, or `-` if
# that header is not present.
#
::oo::define ::tanzer::request method referer {} {
    if {[my headerExists Referer]} {
        return [my header Referer]
    }

    return "-"
}

##
# Returns the value of the `User-Agent:` header of the current request, or
# the string `(unknown)` if the header is not present.
#
::oo::define ::tanzer::request method agent {} {
    if {[my headerExists User-Agent]} {
        return [my header User-Agent]
    }

    return "(unknown)"
}

##
# Return the Unix epoch timestamp corresponding to the data in which the
# current request object was created.
#
::oo::define ::tanzer::request method timestamp {} {
    my variable timestamp

    return $timestamp
}
