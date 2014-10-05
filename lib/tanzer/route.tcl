package provide tanzer::route 0.0.1
package require tanzer::uri
package require TclOO

::oo::class create ::tanzer::route

::oo::define ::tanzer::route constructor {_method _pattern _script} {
    my variable method script pattern

    set method  $_method
    set script  $_script
    set pattern [::tanzer::uri::parts $_pattern]
}

::oo::define ::tanzer::route destructor {
    my variable pattern

    $pattern destroy
}

::oo::define ::tanzer::route method method {} {
    my variable method

    return $method
}

::oo::define ::tanzer::route method pattern {} {
    my variable pattern

    return $pattern
}

::oo::define ::tanzer::route method script {} {
    my variable script

    return $script
}

#
# Given an ::tanzer::uri object, return the relative path string matched by the
# ending glob.
#
::oo::define tanzer::route method relative {path} {
    my variable pattern

    set relativeParts [list]

    set pathLen [llength $path]

    if {$pathLen < [llength $pattern]} {
        error "Request path is shorter than route path"
    }

    set wildcard 0

    for {set i 0} {$i < $pathLen} {incr i} {
        set partRoute [lindex $pattern $i]
        set partPath  [lindex $path    $i]

        if {$partRoute eq "*"} {
            set wildcard 1
        }

        if {$wildcard} {
            lappend relativeParts $partPath
        } elseif {$partRoute ne $partPath} {
            error "Path does not match route"
        }
    }

    return $relativeParts
}
