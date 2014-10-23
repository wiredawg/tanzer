package provide tanzer::file 0.1
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

::oo::define ::tanzer::file constructor {newPath newSt newConfig} {
    my variable config path fh st etag

    set required {
        readBufferSize
    }

    foreach requirement $required {
        if {[dict exists $newConfig $requirement]} {
            set config($requirement) [dict get $newConfig $requirement]
        } else {
            error "Required configuration value $requirement not provided"
        }
    }

    set       path $newPath
    set       etag {}
    array set st   $newSt

    if {$st(type) ne "file"} {
        error "Unsupported operation on file of type $st(type)"
    }

    set fh [open $newPath]

    fconfigure $fh \
        -translation binary \
        -buffering   none \
        -blocking    1
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
    my variable path st etag

    if {$etag ne {}} {
        return $etag
    }

    return [set etag [::sha1::sha1 -hex [concat \
        $path $st(mtime) $st(ino)]]]
}

::oo::define ::tanzer::file method entityMatches {etag} {
    if {[regexp {^"([^\"]+)"$} $etag {} quoted]} {
        set etag $quoted
    }

    return [expr {$etag eq "*" || $etag eq [my etag]}]
}

::oo::define ::tanzer::file method entityNewerThan {rfc2616} {
    my variable st

    return [expr {$st(mtime) > [::tanzer::date::epoch $rfc2616]}]
}

::oo::define ::tanzer::file method match {request} {
    if {![$request headerExists If-Match]} {
        return 1
    }

    return [my entityMatches [$request header If-Match]]
}

::oo::define ::tanzer::file method noneMatch {request} {
    if {![$request headerExists If-None-Match]} {
        return 1
    }

    return [expr {![my entityMatches [$request header If-None-Match]]}]
}

::oo::define ::tanzer::file method modifiedSince {request} {
    if {![$request headerExists If-Modified-Since]} {
        return 1
    }

    return [my entityNewerThan [$request header If-Modified-Since]]
}

::oo::define ::tanzer::file method unmodifiedSince {request} {
    if {![$request headerExists If-Unmodified-Since]} {
        return 1
    }

    return [expr {![my entityNewerThan [$request header If-Unmodified-Since]]}]
}

::oo::define ::tanzer::file method mismatched {} {
    return 0
}

::oo::define ::tanzer::file method stream {event session} {
    my variable fh config

    fcopy $fh [$session sock] -size $config(readBufferSize)

    if {[eof $fh]} {
        $session nextRequest
        my destroy
    }

    return
}

::oo::define ::tanzer::file method headers {} {
    my variable st

    set headers [dict create]

    dict set headers Content-Type   [my mimeType]
    dict set headers Content-Length $st(size)
    dict set headers Etag           "\"[my etag]\""
    dict set headers Accept-Ranges  "bytes"
    dict set headers Last-Modified  [::tanzer::date::rfc2616 $st(mtime)]

    return $headers
}
