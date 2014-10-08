package provide tanzer::logger 0.0.1
package require tanzer::date
package require tanzer::uri
package require TclOO

namespace eval ::tanzer::logger {}

proc ::tanzer::logger::format {subcommand args} {
    switch -- $subcommand "log" {
        set server  [lindex $args 0]
        set session [lindex $args 1]
        set request [$session request]

        if {[llength $args] == 3} {
            set response [lindex $args 2]
        } else {
            set response [$session response]
        }

        return [::format {%s %s - [%s] "%s %s %s" %d %d "%s" "%s"} \
            [$request client] \
            [$request host] \
            [$request timestamp] \
            [$request method] \
            [::tanzer::uri::text [$request uri]] \
            [$request proto] \
            [$response code] \
            [$response length] \
            [$request referer] \
            [$request agent]]
    } "err" {
        set server [lindex $args 0]

        return [concat [lrange $args 1 end] $::errorInfo]
    }

    error "Invalid subcommand $subcommand"
}

proc ::tanzer::logger::default {subcommand args} {
    puts [::tanzer::logger::format $subcommand {*}$args]
}

::oo::class create ::tanzer::logger

::oo::define ::tanzer::logger constructor {opts} {
    my variable config files

    set defaults {
        logStackTraces 1
    }

    set requirements {
        accessLog "No access log file provided"
        errorLog  "No error log file provided"
    }

    array set config $defaults

    foreach {name message} $requirements {
        if {![dict exists $opts $name]} {
            error "$message in option '$name'"
        }

        set config($name) [dict get $opts $name]
    }

    foreach {name unused} $defaults {
        if {[dict exists $opts $name]} {
            set config($name) [dict get $opts $name]
        }
    }

    my open
}

::oo::define ::tanzer::logger method close {} {
    my variable files

    foreach key {accessLog errorLog} {
        if {[array get config $key] ne {}} {
            close $files($key)
        }

        unset files($key)
    }

    return
}

::oo::define ::tanzer::logger method open {} {
    my variable config files

    foreach key {accessLog errorLog} {
        #
        # If any log files are already open, then close and reopen them.
        #
        if {[array get files $key] ne {}} {
            close $files($key)
        }

        set files($key) [::open $config($key) a]
    }

    return
}

::oo::define ::tanzer::logger method write {dest line} {
    my variable files

    puts $files($dest) $line
    flush $files($dest)
}

::oo::define ::tanzer::logger method log {server session args} {
    my write accessLog [::tanzer::logger::format log $server $session {*}$args]

    return
}

::oo::define ::tanzer::logger method err {server error} {
    my variable config

    my write errorLog [::tanzer::logger::format err $server $error]

    if {$config(logStackTraces)} {
        my write errorLog $::errorInfo
    }

    return
}
