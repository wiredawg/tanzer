package provide tanzer::file 0.0.1
package require tanzer::response
package require tanzer::error

package require fileutil::magic::mimetype
package require TclOO
package require sha1

namespace eval ::tanzer::file {}

proc ::tanzer::file::mimeType {path} {
    set mimeType [lindex [::fileutil::magic::mimetype $path] 0]

    switch -glob -nocase $path {
        *.txt  { return "text/plain" }
        *.htm -
        *.html { return "text/html" }
        *.css  { return "text/css" }
        *.png  { return "image/png" }
        *.jpg -
        *.jpeg { return "image/jpeg" }
        *.gif  { return "image/gif" }
    }

    return "application/octet-stream"
}

::oo::class create ::tanzer::file

::oo::define ::tanzer::file constructor {_path _st _config} {
    my variable path fh st config

    set required {
        readBufferSize
    }

    foreach requirement $required {
        if {[dict exists $_config $requirement]} {
            set config($requirement) [dict get $_config $requirement]
        } else {
            error "Required configuration value $requirement not provided"
        }
    }

    set       path $_path
    array set st   $_st

    if {$st(type) ne "file"} {
        error "Unsupported operation on file of type $st(type)"
    }

    set fh [open $_path]

    fconfigure $fh \
        -translation binary \
        -blocking    0
}

::oo::define ::tanzer::file destructor {
    my close
}

::oo::define ::tanzer::file method close {} {
    my variable fh

    if {$fh ne {}} {
        ::close $fh
    }
}

::oo::define ::tanzer::file method mimeType {} {
    my variable path

    return [::tanzer::file::mimeType $path]
}

::oo::define ::tanzer::file method etag {} {
    my variable path st

    return [::sha1::sha1 -hex [concat \
        $path $st(mtime) $st(ino)]]
}

::oo::define ::tanzer::file method matches {etag} {
    if {[regexp {^"([^\"]+)"$} $etag {} quoted]} {
        set etag $quoted
    }

    return [expr {$etag eq "*" || $etag eq [my etag]}]
}

::oo::define ::tanzer::file method stream {event session data} {
    my variable fh config

    fcopy $fh [$session sock] -size $config(readBufferSize)

    if {[eof $fh]} {
        $session nextRequest
        my destroy
        return
    }

    return
}

::oo::define ::tanzer::file method serve {session} {
    my variable config path st

    #
    # Ensure the session object can cleanup the current file state if need
    # be.
    #
    $session cleanup [self] destroy

    set request [$session request]
    set method  [$request method]

    #
    # If a Range: header was specified, then endeavor to serve up ranges for
    # each write ready event.
    #
    if {[$request headerExists Range]} {
        my serve $session

        return
    }

    set response [::tanzer::response new 200]
    set etag     [my etag]
    set serve    1

    $response header Content-Type   [my mimeType]
    $response header Etag           "\"$etag\""
    $response header Accept-Ranges  "bytes"
    $response header Last-Modified  [::tanzer::date::rfc2616 $st(mtime)]

    if {[$request headerExists If-Match]} {
        if {![my matches [$request header If-Match]]} {
            $response status 412
            set serve 0
        }
    } elseif {[$request headerExists If-None-Match]} {
        if {[my matches [$request header If-None-Match]]} {
            $response status 304
            set serve 0
        }
    }

    if {!$serve} {
        $response header Content-Length 0

        $session send $response
        $session nextRequest

        return
    }

    $response header Content-Length $st(size)

    if {$method eq "GET"} {
        $session send $response
        $session delegate [self] stream

        return
    } elseif {$method eq "HEAD"} {
        $session send $response
        $session nextRequest

        return
    }

    ::tanzer::error throw 405 "Method $method unsupported"
}
