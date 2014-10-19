package provide tanzer::route 0.0.1
package require tanzer::error
package require tanzer::uri
package require TclOO

::oo::class create ::tanzer::route

::oo::define ::tanzer::route constructor {newMethod newPattern newHost newScript} {
    my variable method pattern host script

    set method  $newMethod
    set host    $newHost
    set script  $newScript
    set pattern [::tanzer::uri::parts $newPattern]
}

::oo::define ::tanzer::route destructor {
    my variable pattern

    $pattern destroy
}

::oo::define ::tanzer::route method host {} {
    my variable host

    return $host
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
        ::tanzer::error throw 416 "Request path is shorter than route path"
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
            ::tanzer::error throw 416 error "Path does not match route"
        }
    }

    return $relativeParts
}
