package provide tanzer::file::handler 0.1

##
# @file tanzer/file/handler.tcl
#
# The file request handler
#

package require tanzer::file::listing
package require tanzer::file::partial
package require tanzer::file
package require tanzer::error
package require tanzer::response
package require TclOO

##
# The file request handler class.  Provides read-only static file service.
#
::oo::class create ::tanzer::file::handler

##
# The following values should be specified in a list of key-value pairs in
# `$opts`:
#
# * `listings`
#
#   A boolean indicating whether directory listings should be enabled.  Default
#   value is `0`.
#
# * `index`
#
#   A list of index files to look for when serving a request for a directory
#   path.  The first item in this list found is served.  Default value is a
#   single element, `index.html`.
#
# * `filters`
#
#   A list of key-value pairs indicating special filters to apply to files
#   whose base names match a regular expression in the key portion of each
#   pair, and a command prefix which is called with the following values
#   appended:
#
#   * `$session`
#
#     A reference to the originating session
#
#   * `$localPath`
#
#     A string containing the local path of the file to be transformed
#
#   * `$st`
#
#     A `dict` of data as returned by `[file stat]`
#   .
# .
#
# In order to facilitate service of file hierarchies, the file request handler
# should be bound to a wildcard glob route path, such as `/foo/*`.
#
::oo::define ::tanzer::file::handler constructor {opts} {
    my variable config

    set defaults {
        listings 0
        index    {index.html}
        filters  {}
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

##
# Not intended for use as a public method.
#
# Given the path component of the request URI in `$request`, and the parts of
# the path that match everything at and after any possible `*` glob portion
# of the path glob in `$route`, determine the location of the local file to be
# served.
#
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

    return [join [concat [list $config(root)] $relative] "/"]
}

::oo::define ::tanzer::file::handler method filter {session localPath st} {
    my variable config

    set name [file tail $localPath]

    foreach {pattern filter} $config(filters) {
        if {[regexp $pattern $name]} {
            return $filter
        }
    }

    return
}

::oo::define ::tanzer::file::handler method serve {session localPath st} {
    #
    # If there is a filter found for the current file, then delegate all future
    # events to that and bail.
    #
    set filter [my filter $session $localPath $st]

    if {$filter ne {}} {
        $session bind readable {}
        $session bind writable {*}$filter $session $localPath $st

        return
    }

    set request [$session request]
    set method  [$request method]
    set range   [$request headerExists Range]
    set serve   1

    set file [if {$range} {
        ::tanzer::file::partial new $localPath $st [$session config] $request
    } else {
        ::tanzer::file new $localPath $st [$session config]
    }]

    $session cleanup $file destroy

    #
    # Otherwise, proceed to serve the file as normal.
    #
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

    $session response -new [::tanzer::response new [expr {$range? 206: 200}]]
    $session response headers [$file headers]

    #
    # If this is a Range: request, then check to see any If-Range: precondition
    # matches, and set the status to 200 and serve the whole file if not.
    #
    if {$range && [$file mismatched]} {
        $session response status 200
    }

    #
    # If any preconditions are present and fail, then modify the status and do
    # not send a response body.
    #
    set failStatus 304

    set preconditions {
        match noneMatch modifiedSince unmodifiedSince
    }

    foreach precondition $preconditions {
        if {![$file $precondition $request]} {
            $session response status $failStatus
            $session response header Content-Length 0

            set serve 0

            break
        }
    }

    $session respond

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
    foreach item $config(index) {
        set indexFile "$localPath/$item"

        if {![catch {file stat $indexFile indexSt}]} {
            if {$indexSt(type) ne "file"} {
                ::tanzer::error throw 403 "$indexFile is not a file"
            }

            ::tanzer::error run {
                my serve $session $indexFile [array get indexSt]
            }

            return
        }
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
    $session response -new [::tanzer::file::listing new $request $localPath $st]
    $session respond
    $session nextRequest
}

::oo::define ::tanzer::file::handler method read {session data} {
    return
}

::oo::define ::tanzer::file::handler method write {session} {
    my variable config

    set request [$session request]
    set route   [$session route]

    set localPath [my resolve $request $route]

    ::tanzer::error run {
        file stat $localPath st
    }

    if {$st(type) eq "directory"} {
        ::tanzer::error run {
            my index $session $localPath [array get st]
        }

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
