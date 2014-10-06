package provide tanzer::logger 0.0.1
package require tanzer::date
package require tanzer::uri
package require TclOO

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
        if {[array get config $key] ne {}} {
            close $files($key)
        }

        set files($key) [::open $config($key) a]
    }

    return
}

::oo::define ::tanzer::logger method log {server session response} {
    my variable files

    set request [$session request]

    puts $files(accessLog) [format {%s %s - [%s] "%s %s %s" %d %d "%d" "%d"} \
        [$request env REMOTE_ADDR] \
        [info hostname] \
        [$request timestamp] \
        [$request method] \
        [::tanzer::uri::text [$request uri]] \
        [$request env SERVER_PROTOCOL] \
        [$response code] \
        [$response length] \
        [$request referer] \
        [$request agent]]

    return
}

::oo::define ::tanzer::logger method err {server error} {
    my variable config files

    if {$config(logStackTraces)} {
        puts $files(errorLog) $::errorInfo
    } else {
        puts $files(errorLog) $error
    }

    return
}
