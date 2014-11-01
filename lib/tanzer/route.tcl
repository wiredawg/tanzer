package provide tanzer::route 0.1

##
# @file tanzer/route.tcl
#
# The HTTP request handler route specification object
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
::oo::class create ::tanzer::route

##
# Create a new route object with the specified case-insensitive HTTP method 
# regular expression in `$newMethod`, request path pattern in `$newPattern`,
# `Host:` header match pattern in `$newHost`, and request handler in
# `$newScript`.
#
::oo::define ::tanzer::route constructor {newMethod newPattern newHost newScript} {
    my variable method pattern host script

    if {[catch {regexp $newHost ""}]} {
        error "Invalid host pattern $newHost"
    }

    set method  $newMethod
    set host    $newHost
    set script  $newScript
    set pattern [::tanzer::uri::parts $newPattern]
}

::oo::define ::tanzer::route destructor {
    my variable pattern

    $pattern destroy
}

##
# Returns the host matching regular expression for the current route.
#
::oo::define ::tanzer::route method host {} {
    my variable host

    return $host
}

##
# Returns the method routing regular expression for the current route.
#
::oo::define ::tanzer::route method method {} {
    my variable method

    return $method
}


##
# Returns the request path routing pattern for the current route.
#
::oo::define ::tanzer::route method pattern {} {
    my variable pattern

    return $pattern
}

##
# Returns the request handler callback script for the current route.
#
::oo::define ::tanzer::route method script {} {
    my variable script

    return $script
}

##
# Given an ::tanzer::uri object in `$path`, return the relative path string
# matched by the ending glob.
#
::oo::define tanzer::route method relative {path} {
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
