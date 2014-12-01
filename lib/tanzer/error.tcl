package provide tanzer::error 0.1

##
# @file tanzer/error.tcl
#
# Error handling and reporting facilities
#

package require tanzer::response

##
# Provides structured error handling and reporting facilties as a namespace
# ensemble.
#
# Structured exceptions are used to indicate to ::tanzer::server that an error
# is generated intentionally in response to an expected type of error
# condition, be it due to a malformed request or a malformed response from an
# external program.
#
namespace eval ::tanzer::error {
    namespace ensemble create
    namespace export   new throw try fatal response run servable status
    variable  fatal    "The server was unable to fulfill your request."
}

##
# Called as `[::tanzer::error new]`.
#
# Create a new error object, representing an HTTP status code in `$status` and
# a human readable text representation in `$msg`.
#
proc ::tanzer::error::new {status msg} {
    return [list [namespace current] $status $msg]
}

##
# Called as `[::tanzer::error throw]`.
#
# Create and throw a new error object, representing an HTTP status code in
# `$status` and a human readable text representation in `$msg`.
#
proc ::tanzer::error::throw {status msg} {
    error [::tanzer::error new $status $msg]
}

##
# Called as `[::tanzer::error run]`.
#
# Run the code specified in `$script`, and catch any errors.  If the program
# encounters any structured exceptions thrown by the script body, then those
# are passed on with `[error]`.  Otherwise, a new 500 Internal Server Error
# is generated with the message of the error thrown by `$script`.
#
# Certain error conditions cause specific ::tanzer::error objects to be
# generated.
#
# * If `$::errorCode` indicates an `ENOTDIR` or an `ENOENT`, then a 404 File
#   Not Found is thrown.
#
# * If `$::errorCode` indicates an `EPERM`, then a 403 Forbidden is thrown.
#
# * All other error conditions result in a 500 Internal Server Error.
# .
#
proc ::tanzer::error::run {script} {
    if {[catch {uplevel 1 $script} error]} {
        lassign $::errorCode type errno msg

        if {[::tanzer::error servable $error]} {
            error $error
        } else {
            switch -- $errno ENOTDIR - ENOENT {
                ::tanzer::error throw 404 $msg
            } EPERM - EACCES {
                ::tanzer::error throw 403 $msg
            } default {
                error $::errorInfo
            }
        }
    }
}

##
# Called as `[::tanzer::error servable]`.
#
# Returns a boolean indicating whether or not the error passed in `$error` can
# be served as an error page without a wrapper.  In other words, this function
# returns true if `$error` is a ::tanzer::error object, and false if it is not.
#
proc ::tanzer::error::servable {error} {
    return [expr {[string first "[namespace current] " $error] == 0}]
}

##
# Called as `[::tanzer::error try]`.
#
# Run `$script` through `[catch]`; if any errors are thrown, then they will be
# captured in a variable named in `$ename` and provided to the error handling
# code in `$catchBlock`.
#
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

##
# Called as `[::tanzer::error fatal]`.
#
# Generate a new 500 Internal Server Error.
#
proc ::tanzer::error::fatal {} {
    return [::tanzer::error new 500 $::tanzer::error::fatal]
}

##
# Called as `[::tanzer::error response]`.
#
# Generate a new ::tanzer::response object based on the ::tanzer::error object
# specified in `$error`.  A full HTML response is generated, and the response
# body containing error text and a stylized page is buffered.  The response
# object will be ready to be served by a ::tanzer::session session handler.
#
proc ::tanzer::error::response {error} {
    lassign $error ns status msg

    set name [::tanzer::response::lookup $status]

    if {$ns ne [namespace current]} {
        error "Unrecognized error type $ns"
    }

    set response [::tanzer::response new $status {
        Content-Type "text/html"
    }]

    $response buffer [string map [list \
        @status $status \
        @name   $name \
        @msg    [string toupper $msg 0 0] \
    ] {
        <html>
        <head>
            <title>@status @name</title>
            <style type="text/css">
                body {
                    font-family: "HelveticaNeue-Light", "Helvetica Neue", Helvetica;
                    background: #ffffff;
                    color: #4a4a4a;
                    margin: 0px;
                }

                div.tanzer-header {
                    width: 75%;
                    font-size: 30pt;
                    font-weight: bold;
                    padding: 8px;
                    margin-top: 8px;
                    margin-left: auto;
                    margin-right: auto;
                    margin-bottom: 8px;
                }

                div.tanzer-body {
                    background-color: #f0f0f0;
                    border: 0px;
                    padding: 8px;
                    margin-left: auto;
                    margin-right: auto;
                    width: 75%;
                }

                div.tanzer-footer {
                    width: 75%;
                    padding: 8px;
                    margin-top: 8px;
                    margin-left: auto;
                    margin-right: auto;
                    font-size: 10pt;
                }
            </style>
        </head>
        <div class="tanzer-header">
            @status @name
        </div>
        <div class="tanzer-body">
            @msg
        </div>
        <div class="tanzer-footer">
    }]

    $response buffer "Generated by $::tanzer::server::name/$::tanzer::server::version"

    $response buffer {
        </div>
        </body>
        </html>
    }

    return $response
}

##
# Called as `[::tanzer::error status]`.
#
# Return the error status code in the ::tanzer::error object specified in `$e`.
#
proc ::tanzer::error::status {e} {
    if {![::tanzer::error servable $e]} {
        return 500
    }

    return [lindex $e 1]
}
