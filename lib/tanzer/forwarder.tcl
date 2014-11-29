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
# The HTTP request forwarding base class.
#
::oo::class create ::tanzer::forwarder

##
# Create a new HTTP request forwarder.
#
# Options include:
#
# * `rewrite`
# 
#   A list of regex, `[format]` pairs which, upon the regex matching a literal
#   request URI string, will replace the URI with a new string produced from
#   the formatted regular expression subexpression matches.  For instance:
#
#   @code
#   ::tanzer::forwarder new {
#       rewrite {
#           {/git?repo_name=/(.*)\.git$}             "/git/%s"
#           {/git?repo_name=/(.*)\.git&commit=(.*)$} "/git/%s/commits/%s"
#       }
#   }
#   @endcode
# .
#
::oo::define ::tanzer::forwarder constructor {opts} {
    my variable rewrite

    set rewrite [if {[dict exists $opts rewrite]} {
        dict get $opts rewrite
    } else {
        list
    }]
}

::oo::define ::tanzer::forwarder method cleanup {session} {
    error "Not implemented"
}

::oo::define ::tanzer::forwarder method open {session} {
    my variable rewrite

    set request [$session request]

    foreach {re newFormat} $rewrite {
        if {[$request rewrite $re $newFormat]} {
            break
        }
    }
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

::oo::define ::tanzer::forwarder method close {session} {
    my cleanup $session

    $session nextRequest

    return
}
