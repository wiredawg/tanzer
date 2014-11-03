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

::oo::define ::tanzer::forwarder method close {session} {
    my cleanup $session

    $session nextRequest

    return
}

##
# Begin an asynchronous background [fcopy] operation from `$in` to `$out`,
# ending when `$in` has reached end-of-file status.  Any errors encountered
# along the way are thrown, and the state for `$session` is cleaned up.
#
::oo::define ::tanzer::forwarder method pipe {in out session} {
    foreach event {readable writable} {
        fileevent $out $event {}
    }

    fcopy $in $out -command [list apply {
        {forwarder session copied args} {
            if {[llength $args] > 0} {
                error [lindex $args 0]
            }

            $forwarder close $session
        }
    } [self] $session]

    return
}
