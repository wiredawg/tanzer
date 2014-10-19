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

::oo::define ::tanzer::response constructor {newStatus {newHeaders {}}} {
    my variable version status headers

    next -response

    set version $::tanzer::message::defaultVersion
    set status  $newStatus
    set headers {}

    if {$newHeaders ne {}} {
        my headers $newHeaders
    }
}

::oo::define ::tanzer::response method status {{newStatus ""}} {
    my variable status

    if {$newStatus ne ""} {
        set status $newStatus

        return
    }

    return $status
}
