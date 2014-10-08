package provide tanzer::message 0.0.1
package require TclOO

namespace eval ::tanzer::message {}

proc ::tanzer::message::field {name} {
    set parts [split $name -]
    set new   [list]

    foreach part $parts {
        lappend new [string toupper [string tolower $part] 0 0]
    }

    return [join $new -]
}

::oo::class create ::tanzer::message

::oo::define ::tanzer::message constructor {args} {
    my variable headers
    
    set headers {}

    if {[llength $args] == 1} {
        my headers [lindex $args 0]
    }
}

::oo::define ::tanzer::message method header {name args} {
    my variable headers

    if {[llength $args] == 0} {
        return [dict get $headers [::tanzer::message::field $name]]
    } elseif {[llength $args] == 1} {
        set name  [::tanzer::message::field $name]
        set value [lindex $args 0]

        lappend headers $name $value

        return [list $name $value]
    }

    error "Invalid command invocation"
}

::oo::define ::tanzer::message method headers {args} {
    my variable headers

    if {[llength $args] == 0} {
        set ret {}

        foreach {name value} $headers {
            lappend ret [::tanzer::message::field $name] $value
        }

        return $ret
    }

    if {[llength $args] == 1} {
        foreach {name value} [lindex $args 0] {
            my header $name $value
        }

        return $headers
    }

    if {{llength $args} % 2 == 0} {
        foreach {name value} $args {
            my header $name $value
        }

        return $headers
    }

    error "Invalid arguments"
}

::oo::define ::tanzer::message method headerExists {key} {
    my variable headers

    return [dict exists $headers $key]
}

::oo::define ::tanzer::message method length {} {
    if {[my headerExists Content-Length]} {
        return [my header Content-Length]
    }

    return 0
}
