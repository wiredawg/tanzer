package provide tanzer::response 0.0.1
package require tanzer::message
package require TclOO

namespace eval ::tanzer::response {
    variable codes

    array set codes {
        200 "OK"
        206 "Partial Content"
        301 "Moved Permanently"
        403 "Forbidden"
        404 "Not Found"
        500 "Internal Server Error"
    }
}

proc ::tanzer::response::lookup {code} {
    variable codes

    if {[array get codes $code] ne {}} {
        return $codes($code)
    }

    return ""
}

::oo::class create ::tanzer::response {
    superclass ::tanzer::message
}

::oo::define ::tanzer::response constructor {_code args} {
    my variable code headers data

    set code    $_code
    set headers {}
    set data    ""

    if {[llength $args] > 0} {
        my headers [lindex $args 0]
    }
}

::oo::define ::tanzer::response method data {} {
    my variable data

    return $data
}

::oo::define ::tanzer::response method buffer {_data} {
    my variable data

    append data $_data
}

::oo::define ::tanzer::response method write {sock} {
    my variable code headers data

    puts -nonewline $sock [format "HTTP/1.1 %d %s\r\n" \
        $code [::tanzer::response::lookup $code]]

    set len [string length $data]

    if {$len > 0} {
        my header Content-Length $len
    }

    foreach {name value} $headers {
        puts -nonewline $sock "[::tanzer::message::field $name]: $value\r\n"
    }

    puts -nonewline $sock "\r\n"

    if {$len > 0} {
        puts -nonewline $sock $data
    }
}
