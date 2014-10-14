package provide tanzer::http::request 0.0.1
package require tanzer::request
package require tanzer::error
package require tanzer::uri
package require TclOO

namespace eval ::tanzer::http::request {
    variable proto "http"
}

::oo::class create ::tanzer::http::request {
    superclass ::tanzer::request
}

::oo::define ::tanzer::http::request constructor {session} {
    next $session
}
