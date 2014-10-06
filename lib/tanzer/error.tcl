package provide tanzer::error 0.0.1
package require tanzer::response

namespace eval ::tanzer::error {
    namespace ensemble create
    namespace export new throw try response run servable
}

proc ::tanzer::error::new {code msg} {
    return [list [namespace current] $code $msg]
}

proc ::tanzer::error::throw {code msg} {
    error [::tanzer::error new $code $msg]
}

proc ::tanzer::error::run {script} {
    if {[catch {set ret [uplevel 1 $script]} error]} {
        set type  [lindex $::errorCode 0]
        set errno [lindex $::errorCode 1]
        set msg   [lindex $::errorCode 2]

        if {[::tanzer::error servable $error]} {
            error $error
        } else {
            switch -- $errno ENOTDIR - ENOENT {
                ::tanzer::error throw 404 $msg
            } EPERM {
                ::tanzer::error throw 403 $msg
            } default {
                ::tanzer::error throw 500 $error
            }
        }
    }

    return $ret
}

proc ::tanzer::error::servable {error} {
    return [expr {[string first "[namespace current] " $error] == 0}]
}

proc ::tanzer::error::try {script catch ename catchBlock} {
    set ret {}

    if {$catch ne "catch"} {
        error "Invalid command invocation"
    }

    if {[catch {set ret [uplevel 1 $script]} error]} {
        return [uplevel 1 [join [list \
            [list set $ename $error] \
            $catchBlock] "\n"]]
    }

    return $ret
}

proc ::tanzer::error::response {error} {
    set ns   [lindex $error 0]
    set code [lindex $error 1]
    set msg  [lindex $error 2]
    set name [::tanzer::response::lookup $code]

    if {$ns ne [namespace current]} {
        error "Unrecognized error type $ns"
    }

    set response [::tanzer::response new $code {
        Content-Type "text/html"
    }]

    $response buffer [string map [list \
        @code $code \
        @name $name \
        @msg  $msg \
    ] {
        <html>
        <head>
            <title>@code - @name</title>
        </head>
        <h1>@code - @name</h1>
        <p>
            @msg
        </p>
        </body>
        </html>
    }]

    return $response
}
