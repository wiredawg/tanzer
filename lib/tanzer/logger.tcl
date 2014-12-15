package provide tanzer::logger 0.1

##
# @file tanzer/logger.tcl
#
# The tanzer logging facility
#

package require tanzer::date
package require tanzer::uri
package require TclOO

namespace eval ::tanzer::logger {}

proc ::tanzer::logger::format {subcommand args} {
    switch -- $subcommand "err" {
        return [concat $args $::errorInfo]
    } "log" {
        #
    } default {
        error "Invalid subcommand $subcommand"
    }

    lassign $args request response

    return [::format {%s %s - [%s] "%s %s %s" %d %d "%s" "%s"} \
        [$request client] \
        [$request host] \
        [$request timestamp] \
        [$request method] \
        [$request uri] \
        [$request version] \
        [$response status] \
        [$response length] \
        [$request referer] \
        [$request agent]]
}

proc ::tanzer::logger::default {subcommand args} {
    puts [::tanzer::logger::format $subcommand {*}$args]
}

##
# The tanzer logging facility.
#
::oo::class create ::tanzer::logger

##
# Create a new logger.  The following configuration options may be specified in
# `$opts` as a list of key-value pairs:
#
# * `accessLog`
#
#   The path to a file to record incoming requests to.  If this is not
#   specified, then incoming requests will be logged to standard output.
#
# * `errorLog`
#
#   The path to a file to record internal server errors to.  If this is not
#   specified, then internal server errors will be logged to standard output.
#
# * `logStackTraces`
#
#   A boolean value, defaulting to `1`, indicating whether or not to log stack
#   traces when handling error logs.
#
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

##
# Close all log files held by the current logger object.
#
::oo::define ::tanzer::logger method close {} {
    my variable files

    foreach key {accessLog errorLog} {
        if {[array get config $key] ne {}} {
            catch {
                close $files($key)
            }

            unset files($key)
        }
    }

    return
}

##
# Open all log files specified at logger construction time.  If the log files
# are already opened, then they will be closed and reopened.  This may be a
# useful thing if log files are rotated and need to be recreated.
#
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

##
# Write `$line` to the logging destination `$dest` (one of `accessLog` or
# `errorLog`), immediately flushing the output to disk.
#
::oo::define ::tanzer::logger method write {dest line} {
    my variable files

    puts $files($dest) $line
    flush $files($dest)

    return
}

##
# Record the incoming `$request` and its `$response` to the access log.
#
::oo::define ::tanzer::logger method log {request response} {
    if {$request eq {} || $response eq {}} {
        return
    }

    my write accessLog [::tanzer::logger::format log $request $response]

    return
}

##
# Record the specified `$error` to the error log, appending any stack traces if
# `logStackTraces` is set to `1`.
#
::oo::define ::tanzer::logger method err {error} {
    my variable config

    my write errorLog [::tanzer::logger::format err $error]

    if {$config(logStackTraces)} {
        my write errorLog $::errorInfo
    }

    return
}
