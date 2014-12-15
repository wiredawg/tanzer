package provide tanzer::forwarder 0.1

##
# @file tanzer/forwarder.tcl
#
# HTTP request forwarding base functionality
#

package require TclOO

namespace eval ::tanzer::forwarder {
    ##
    # The default status to use when parsing and relaying incoming HTTP
    # messages for forwarding.  Default value is `500`.
    #
    variable defaultStatus 500
}

##
# The HTTP request forwarding base interface class.
#
::oo::class create ::tanzer::forwarder

::oo::define ::tanzer::forwarder constructor {args} {
    error "Not implemented"
}

##
# A method to be implemented by any request forwarder class that allows one to
# clean up any state specific to that request forwarder.
#
::oo::define ::tanzer::forwarder method cleanup {session} {
    error "Not implemented"
}

##
# A method to be implemented by any request forwarder class that allows one to
# open any resources involved in servicing the current request for `$session`.
#
::oo::define ::tanzer::forwarder method open {session} {
    error "Not implemented"
}

##
# Clean up any state associated with `$session`, and allow the session handler to
# yield yield to the next incoming request.
#
::oo::define ::tanzer::forwarder method close {session} {
    my cleanup $session

    $session nextRequest

    return
}

##
# Pipe all remaining data from channel `$in` to client socket `$sock`, and
# yield `$session` to handle the next request.
#
::oo::define ::tanzer::forwarder method pipe {in sock session} {
    foreach event {readable writable} {
        chan event $sock $event {}
    }

    chan copy $in $sock -command [list apply {
        {session copied args} {
            if {[llength $args] > 0} {
                $session error [lindex $args 0]

                return
            }

            $session nextRequest
        }
    } $session]

    return
}
