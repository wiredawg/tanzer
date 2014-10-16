package provide tanzer::file::handler 0.0.1
package require tanzer::file::listing
package require tanzer::file::partial
package require tanzer::file
package require tanzer::error
package require tanzer::response
package require TclOO

::oo::class create ::tanzer::file::handler

::oo::define ::tanzer::file::handler constructor {opts} {
    my variable config

    set defaults {
        listings  0
        indexFile index.html
    }

    set requirements {
        root "No root directory for file handler provided"
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
}

::oo::define ::tanzer::file::handler method resolve {request route} {
    my variable config

    #
    # First, determine where the file ought to live, relative to the root
    # directory to be served by this request.
    #
    set relative [$route relative [$request path]]
    set level 0

    #
    # Next, make sure the request does not attempt to use the stupid old
    # ../ trick.
    #
    foreach item $relative {
        if {$item eq ".."} {
            if {[incr level -1] < 0} {
                ::tanzer::error throw 403 "Invalid request path"
            }
        } elseif {$item eq "."} {
            continue
        } else {
            incr level
        }
    }

    return [join [concat $config(root) $relative] "/"]
}

::oo::define ::tanzer::file::handler method serve {session localPath st} {
    set config   [$session config]
    set request  [$session request]
    set method   [$request method]
    set range    [$request headerExists Range]
    set response [::tanzer::response new [expr {$range? 206: 200}]]
    set serve    1

    set file [if {$range} {
        ::tanzer::file::partial new $localPath $st $config $request
    } else {
        ::tanzer::file new $localPath $st $config
    }]

    $session cleanup $file destroy

    switch -- $method "GET" {#} "HEAD" {
        if {$range} {
            ::tanzer::error throw 405 "Invalid request method with Range:"
        }

        set serve 0
    } default {
        ::tanzer::error throw 400 "Unsupported method $method"
    }

    if {[$request length]} {
        ::tanzer::error throw 415 "Request bodies not allowed for file reads"
    }

    $response headers [$file headers]

    #
    # If this is a Range: request, then check to see any If-Range: precondition
    # matches, and set the status to 200 and serve the whole file if not.
    #
    if {$range && [$file mismatched]} {
        $response status 200
    }

    #
    # If any preconditions are present and fail, then modify the status and do
    # not send a response body.
    #
    set preconditions {
                  match 412
              noneMatch 304
          modifiedSince 412
        unmodifiedSince 304
    }

    foreach {precondition failStatus} $preconditions {
        if {![$file $precondition $request]} {
            $response status $failStatus
            $response header Content-Length 0

            set serve 0

            break
        }
    }

    $session send $response

    if {$serve} {
        $session delegate $file stream
    } else {
        $session nextRequest
    }

    return
}

::oo::define ::tanzer::file::handler method index {session localPath st} {
    my variable config

    set request [$session request]
    set path    [$request path]

    #
    # If the request does not have a trailing slash, then send a 301 redirect
    # to the right place.
    #
    if {[lindex $path end] ne {}} {
        $session redirect [::tanzer::uri::text [concat $path {""}]]
        $session nextRequest

        return
    }

    #
    # Otherwise, look for an index file in the requested directory, and serve
    # that file if it exists.
    #
    set indexFile "$localPath/$config(indexFile)"

    if {![catch {file stat $indexFile indexSt}]} {
        if {$indexSt(type) ne "file"} {
            ::tanzer::error throw 403 "$indexFile is not a file"
        }

        ::tanzer::error run {
            my serve $session $indexFile [array get indexSt]
        }

        return
    }

    #
    # If we must list the directory at this point, at least determine if
    # listings are enabled, and raise an error otherwise.
    #
    if {!$config(listings)} {
        ::tanzer::error throw 403 "Directory listing not allowed"
    }

    #
    # Lastly, send a directory listing.
    #
    set response [::tanzer::file::listing new $request $localPath $st]

    $session send $response
    $session nextRequest
}

::oo::define ::tanzer::file::handler method respond {event session data} {
    my variable config

    if {$event ne "write"} {
        return
    }

    set request [$session request]
    set route   [$session route]

    set localPath [my resolve $request $route]

    ::tanzer::error run {
        file stat $localPath st
    }

    if {$st(type) eq "directory"} {
        my index $session $localPath [array get st]

        return
    }

    if {$st(type) ne "file"} {
        ::tanzer::error throw 403 "Unsupported inode type $st(type)"
    }

    ::tanzer::error run {
        my serve $session $localPath [array get st]
    }

    return
}
