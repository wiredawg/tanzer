package provide tanzer::cgi::handler 0.0.1
package require tanzer::response
package require tanzer::error
package require TclOO
package require Tclx

namespace eval ::tanzer::cgi::handler {
    variable proto "CGI/1.1"
}

::oo::class create ::tanzer::cgi::handler

::oo::define ::tanzer::cgi::handler constructor {opts} {
    my variable config hostname

    set requirements {
        program      "No CGI executable provided"
        scriptName   "No script name provided"
        documentRoot "No document root provided"
    }

    foreach {name message} $requirements {
        if {![dict exists $opts $name]} {
            error "$message in option '$name'"
        }

        set config($name) [dict get $opts $name]
    }

    set hostname [info hostname]
}

::oo::define ::tanzer::cgi::handler method respond {event session data} {
    my variable config pids

    set server  [$session server]
    set route   [$session route]
    set request [$session request]

    set sock [$session sock]
    set addr [lindex [chan configure $sock -sockname] 0]

    set childenv [dict create \
        GATEWAY_INTERFACE $::tanzer::cgi::handler::proto \
        SERVER_SOFTWARE   "$::tanzer::server::name/$::tanzer::server::version" \
        SERVER_ADDR       $addr \
        SERVER_PORT       [$server port] \
        SCRIPT_FILENAME   $config(program) \
        SCRIPT_NAME       $config(scriptName) \
        REQUEST_METHOD    [$request method] \
        PWD               [pwd] \
        DOCUMENT_ROOT     $config(documentRoot)]

    foreach {name value} [$request env] {
        dict set childenv $name $value
    }

    foreach {name value} [$request headers] {
        dict set childenv \
            [string map {"-" "_"} [string toupper $name]] \
            $value
    }

    puts -nonewline $sock "[$request proto] 200 OK\r\n"

    flush stderr
    flush stdout

    set child [fork]

    if {$child == 0} {
        close stderr

        dup $sock stdin
        dup $sock stdout

        array unset ::env
        array set ::env $childenv

        execl $config(program)

        exit 127
    }

    set pids($session) $child

    $session destroy

    return
}
