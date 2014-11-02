package provide tanzer::http::request 0.1

##
# @file tanzer/http/request.tcl
#
# The HTTP request parser facility
#

package require tanzer::request
package require tanzer::error
package require tanzer::uri
package require TclOO

namespace eval ::tanzer::http::request {
    variable proto "http"
}

##
# A minimal wrapper to ::tanzer::request.  Provides no additional facilities,
# as the facilities within ::tanzer::request are sufficiently general for
# parsing HTTP requests from any source.
#
::oo::class create ::tanzer::http::request {
    superclass ::tanzer::request
}
