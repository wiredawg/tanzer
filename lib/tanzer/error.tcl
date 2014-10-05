package provide tanzer::error 0.0.1
package require tanzer::response

namespace eval ::tanzer::error {
    namespace ensemble create
    namespace export new response servable
}

proc ::tanzer::error::new {code msg} {
    return [list [namespace current] $code $msg]
}

proc ::tanzer::error::servable {error} {
    return [expr {[string first "[namespace current] " $error] == 0}]
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
