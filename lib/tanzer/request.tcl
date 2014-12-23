package provide tanzer::request 0.1

##
# @file tanzer/request.tcl
#
# The HTTP/1.1 request object
#

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
    my variable session env headers buffer uri uriOrig \
        path params rewritten timestamp

    next -request

    set date [::tanzer::date new [clock seconds]]

    set session   $newSession
    set env       [dict create]
    set headers   [dict create]
    set uri       {}
    set uriOrig   {}
    set path      {}
    set params    {}
    set rewritten 0
    set timestamp [::tanzer::date rfc2616 $date]
}

##
# Parse the URI passed in `$newUri` for the URL-decoded path component, and the
# query string.  These individual components will be parsed and URL decoded as
# appropriate.  `$newUri` will be saved literally in the current request for
# future reference.
#
# If called with a `$newUri` value multiple times on the same request object,
# the new URI will of course take effect, but internally the original URI will
# be retained; and, when called with no arguments after a new URI was set again,
# the original URI will always be returned.  This is particularly useful in
# helping the request object remember the original URI for accurate logging
# purposes.
#
::oo::define ::tanzer::request method uri {{newUri ""}} {
    my variable uri uriOrig path

    if {$newUri eq ""} {
        return $uriOrig
    }

    if {$uriOrig eq {}} {
        set uriOrig $newUri
    }

    set uri      $newUri
    set uriParts [split $uri "?"]
    set path     [::tanzer::uri::parts [lindex $uriParts 0]]
    set query    [join [lrange $uriParts 1 end] "?"]

    foreach {name value} [::tanzer::uri::params $query] {
        my param $name $value
    }

    my env REQUEST_URI  $uri
    my env QUERY_STRING $query

    return
}

##
# Given a list of regular expression and `[format]` string pairs, iterate through
# the list until the first matching regular expression is encountered, and
# rewrite the URI set in a previous invocation of ::tanzer::request::uri
# accordingly.  Positional format specifiers in the rewrite format are filled in
# with values captured from subexpressions in the matching regular expression.
#
# Repeated calls to this method on the same request object yield no effect, and
# always return 1.  Furthermore, subsequent rewrite calls always perform rewrites
# on the original URI of the request, not the resulting URI from prior rewrite
# operations.
#
# Example:
#
# @code{.tcl}
# $request rewrite {
#     {^/foo/(\d+)$} "/foo-%d.html"
#     {^/bar/(\d+)$} "/images/bar-%d.jpg"
# }
# @endcode
#
::oo::define ::tanzer::request method rewrite {args} {
    my variable uriOrig rewritten

    if {$rewritten} {
        return 1
    }

    if {$uriOrig eq {}} {
        error "Cannot rewrite URI on request that has not been matched"
    }

    foreach {re newFormat} $args {
        set matches [regexp -inline $re $uriOrig]

        if {[llength $matches] == 0} {
            continue
        }

        my uri [format $newFormat {*}[lrange $matches 1 end]]

        return [set rewritten 1]
    }

    return 0
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
# Return the value of the parameter called `$name`, or a value is also provided
# in a second argument, set the value of `$name` to that literal value.
#
::oo::define ::tanzer::request method param {name args} {
    my variable params

    switch -- [llength $args] 0 {
        return [dict get $params $name]
    } 1 {
        return [dict set params $name [lindex $args 0]]
    } default {
        error "Invalid command invocation"
    }
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
# list of key-value pairs.  If only a name is supplied, then return only the
# value of that variable, if it exists.  If a value is also supplied, then set
# an environment variable to that value.
#
::oo::define ::tanzer::request method env {args} {
    my variable env

    switch -- [llength $args] 0 {
        return $env
    } 1 {
        lassign $args name

        return [if {[dict exists $env $name]} {
            dict get $env $name
        } else {
            list ""
        }]
    } 2 {
        lassign $args name value

        return [dict set env $name $value]
    }

    error "Invalid command invocation"
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
