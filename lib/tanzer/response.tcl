package provide tanzer::response 0.1

##
# @file tanzer/response.tcl
#
# The HTTP response object
#

package require tanzer::message
package require TclOO

##
# A namespace containing HTTP statuses.
#
namespace eval ::tanzer::response {
    ##
    # The HTTP statuses that are served and recognized by tanzer.
    #
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

##
# Given the HTTP status code in `$status`, return a text representation
# thereof, or an empty string when passed an unrecognized HTTP status.
#
proc ::tanzer::response::lookup {status} {
    variable statuses

    if {[array get statuses $status] ne {}} {
        return $statuses($status)
    }

    return ""
}

##
# The HTTP response class.
#
::oo::class create ::tanzer::response {
    superclass ::tanzer::message
}

##
# Create a new response object with the status indicated in `$newStatus`.  If
# a list of header/value pairs is provided in `$newHeaders`, then load those
# default headers.
#
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

##
# Return the HTTP status code of the current response.  If a new status is
# provided, then set the status code with the value provided.
#
::oo::define ::tanzer::response method status {args} {
    my variable status

    switch -- [llength $args] 0 {
        return $status
    } 1 {
        return [lassign $args status]
    }

    error "Invalid command invocation"
}
