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

::oo::define ::tanzer::file::handler method close {session} {
    my variable ranges

    if {[array get ranges $session] ne {}} {
        unset ranges($session)
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
    my variable config

    set request [$session request]

    if {[$request headerExists Range]} {
        set file [::tanzer::file::partial new \
            $localPath $st [$session config] $request]
    } else {
        set file [::tanzer::file new \
            $localPath $st [$session config]]
    }

    $file serve $session
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
    my variable config files

    if {$event ne "write"} {
        return
    }

    set request [$session request]
    set route   [$session route]

    #
    # Send an error if the client is trying to send file data.
    #
    if {[$request length]} {
        ::tanzer::error throw 415 "Request bodies not allowed for file reads"
    }

    switch [$request method] {
        GET -
        HEAD {}

        default {
            ::tanzer::error throw 405 "Unsupported method for request"
        }
    }

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
