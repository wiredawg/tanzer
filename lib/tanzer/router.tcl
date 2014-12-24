package provide tanzer::router 0.1

##
# @file tanzer/router.tcl
#
# The request routing table
#

package require tanzer::error
package require tanzer::router::entry
package require TclOO

##
# `::tanzer::router` manages a table of request handlers and matches inbound
# requests to the appropriate handler.
#
::oo::class create ::tanzer::router

##
# Create a new, empty routing table.
#
::oo::define ::tanzer::router constructor {} {
    my variable entries

    set entries [list]
}

::oo::define ::tanzer::router destructor {
    my variable entries

    foreach route $entries {
        $route destroy
    }
}

##
# Add a new route with method `$method` for URI pattern `$pattern`, host regex
# `$host`, and request handler `$args` to the routing table.
#
::oo::define ::tanzer::router method add {method pattern host args} {
    my variable entries

    lappend entries [::tanzer::router::entry new \
        $method $pattern $host $args]
}

##
# Return a list of the current routing table entries.
#
::oo::define ::tanzer::router method entries {} {
    my variable entries

    return $entries
}

##
# Search through the route entries for a route that matches `$request`.
# If no suitable router entry can be matched to the request specified, then
# throw a 404 error.
#
::oo::define ::tanzer::router method route {request} {
    my variable entries

    foreach candidate $entries {
        if {[$candidate matches $request]} {
            return $candidate
        }
    }

    ::tanzer::error throw 404 "No suitable route found"
}
