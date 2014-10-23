package provide tanzer::forwarder 0.1
package require TclOO

namespace eval ::tanzer::forwarder {
    variable defaultStatus 500
}

::oo::class create ::tanzer::forwarder

::oo::define ::tanzer::forwarder constructor {opts} {
    my variable rewrite

    set rewrite [if {[dict exists $opts rewrite]} {
        dict get $opts rewrite
    } else {
        list
    }]
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
