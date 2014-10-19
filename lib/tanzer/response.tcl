package provide tanzer::response 0.0.1
package require tanzer::message
package require TclOO

namespace eval ::tanzer::response {
    variable statuses

    array set statuses {
        200 "OK"
        206 "Partial Content"
        301 "Moved Permanently"
        304 "Not Modified"
        400 "Bad Request"
        403 "Forbidden"
        404 "Not Found"
        405 "Method Not Allowed"
        412 "Precondition Failed"
        415 "Unsupported Media Type"
        416 "Requested Range Not Satisfiable"
        500 "Internal Server Error"
    }
}

proc ::tanzer::response::lookup {status} {
    variable statuses

    if {[array get statuses $status] ne {}} {
        return $statuses($status)
    }

    return ""
}

::oo::class create ::tanzer::response {
    superclass ::tanzer::message
}

::oo::define ::tanzer::response constructor {_status args} {
    my variable version status headers

    next -response

    set version $::tanzer::message::defaultVersion
    set status  $_status
    set headers {}

    if {[llength $args] > 0} {
        my headers [lindex $args 0]
    }
}

::oo::define ::tanzer::response method status {args} {
    my variable status

    switch -- [llength $args] 0 {
        return $status
    } 1 {
        return [set status [lindex $args 0]]
    }

    error "Invalid command invocation"
}
