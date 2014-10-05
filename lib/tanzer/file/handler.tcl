package provide tanzer::file::handler 0.0.1
package require tanzer::file::listing
package require tanzer::file::partial
package require tanzer::file
package require tanzer::response

package require fileutil::magic::mimetype
package require TclOO
package require sha1

namespace eval ::tanzer::file::handler {
    variable boundary "sxw94fa83qpa8"
}

proc ::tanzer::file::handler::mimeType {localPath} {
    set mimeType [lindex [::fileutil::magic::mimetype $localPath] 0]

    if {$mimeType ne {}} {
        return $mimeType
    }

    switch -glob -nocase $localPath {
        *.txt  { return "text/plain" }
        *.htm -
        *.html { return "text/html" }
    }

    return "application/octet-stream"
}

proc ::tanzer::file::handler::ranges {headerValue size} {
    set ranges [list]

    if {![regexp {^bytes=(.*)$} $headerValue {} bytesRanges]} {
        error "Invalid byte range value"
    }

    foreach bytesRange [split $bytesRanges ","] {
        set min 0
        set max [expr $size - 1]

        if {[regexp {^(\d+)-$} $bytesRange {} start]} {
            set min $start
        } elseif {[regexp {^-(\d+)$} $bytesRange {} endOffset]} {
            set min [expr $size - $endOffset]
        } elseif {[regexp {^(\d+)-(\d+)$} $bytesRange {} start end]} {
            set min $start
            set max $end
        } else {
            error "Invalid byte range value"
        }

        if {$min < 0 || $min >= $size || $max >= $size || $max < 0} {
            error "Invalid byte range value"
        }

        lappend ranges [list $min $max]
    }

    return $ranges
}

proc ::tanzer::file::handler::etag {localPath st} {
    return [::sha1::sha1 -hex [concat \
        $localPath \
        [dict get $st mtime] \
        [dict get $st ino]]]
}

::oo::class create ::tanzer::file::handler

::oo::define ::tanzer::file::handler constructor {opts} {
    my variable config

    set defaults {
        listings  0
        indexFile index.html
    }

    set requirements {
        root   "No root directory for file handler provided"
        static "No static resources directory for file listings provided"
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
    my variable files ranges

    if {[array get files $session] ne {}} {
        ::close $files($session)
        unset files($session)
    }

    if {[array get ranges $session] ne {}} {
        unset ranges($session)
    }
}

::oo::define ::tanzer::file::handler method open {session localPath} {
    my variable config files

    set fh [::open $localPath]

    fconfigure $fh \
        -translation binary \
        -blocking    0 \
        -buffering   full \
        -buffersize  [$session config readBufferSize]

    return [set files($session) $fh]
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
                error "Invalid request path"
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
        $session send [$session redirect \
            [::tanzer::uri::text [concat $path {""}]]]

        $session destroy

        return
    }

    #
    # Otherwise, look for an index file in the requested directory, and serve
    # that file if it exists.
    #
    set indexFile "$localPath/$config(indexFile)"

    if {![catch {file stat $indexFile indexSt}]} {
        if {$indexSt(type) ne "file"} {
            error "$indexFile is not a file"
        }
        
        my serve $session $indexFile [array get indexSt]

        return
    }

    #
    # Lastly, send a directory listing.
    #
    set response [::tanzer::file::listing new $request $localPath $st]

    $session send $response

    $response destroy
    $session  destroy
}

::oo::define ::tanzer::file::handler method respond {event session data} {
    my variable config files

    if {$event ne "write"} {
        return
    }

    set request [$session request]
    set route   [$session route]

    switch [$request method] {
        GET -
        HEAD {}

        default {
            error "Unsupported method for request"
        }
    }

    set localPath [my resolve $request $route]

    file stat $localPath st

    if {$st(type) eq "directory"} {
        my index $session $localPath [array get st]

        return
    }

    if {$st(type) ne "file"} {
        error "Unsupported inode type $st(type)"
    }

    my serve $session $localPath [array get st]

    return
}
