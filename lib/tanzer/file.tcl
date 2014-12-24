package provide tanzer::file 0.1

##
# @file tanzer/file.tcl
#
# Static file service
#

package require tanzer::response
package require tanzer::error
package require TclOO

namespace eval ::tanzer::file {
    variable mimeTypes {
        {\.txt$}          "text/plain"
        {\.(?:htm|html)$} "text/html"
        {\.css$}          "text/css"
        {\.png$}          "image/png"
        {\.(?:jpg|jpeg)$} "image/jpeg"
        {\.gif$}          "image/gif"
        {\.tar\.gz$}      "application/x-tgz"
        {\.tgz$}          "application/x-tgz"
        {\.gz$}           "application/x-gzip"
        {\.m4a$}          "audio/mp4a-latm"
        {\.}              "application/octet-stream"
    }
}

##
# An object representing an open, servable file.
#
::oo::class create ::tanzer::file

##
# Open a file at `$newPath`, passing information returned from `[file stat]`
# as a list in `$newSt`, and a list of key-value configuration pairs in
# `$newConfig`.
#
# Configuration values required in `$newConfig`:
#
# * `readsize`
# 
#   The number of bytes of a file to read at a time.
#
::oo::define ::tanzer::file constructor {newPath newSt newConfig} {
    my variable config path fh st etag mimeType

    set required {
        readsize
    }

    foreach requirement $required {
        if {[dict exists $newConfig $requirement]} {
            set config($requirement) [dict get $newConfig $requirement]
        } else {
            error "Required configuration value $requirement not provided"
        }
    }

    set       path     $newPath
    set       etag     {}
    set       mimeType {}
    array set st       $newSt

    if {$st(type) ne "file"} {
        error "Unsupported operation on file of type $st(type)"
    }

    set fh [open $newPath]

    chan configure $fh      \
        -translation binary \
        -blocking    1      \
        -buffering   none
}

::oo::define ::tanzer::file destructor {
    my close
}

##
# Close the file channel held by the current ::tanzer::file object.
#
::oo::define ::tanzer::file method close {} {
    my variable fh

    if {$fh ne {}} {
        catch {
            ::close $fh
        }
    }
}

##
# Return the MIME type of the current file.
#
::oo::define ::tanzer::file method mimeType {} {
    my variable path mimeType

    if {$mimeType ne {}} {
        return $mimeType
    }

    set name [file tail $path]

    foreach {pattern type} $::tanzer::file::mimeTypes {
        if {[regexp -nocase $pattern $name]} {
            return [set mimeType $type]
        }
    }

    return [set mimeType "application/octet-stream"]
}

##
# Return an RFC 2616 Entity Tag describing the current file.
#
::oo::define ::tanzer::file method etag {} {
    my variable path st etag

    if {$etag ne {}} {
        return $etag
    }

    return [set etag [format "%x%x%x" $st(dev) $st(ino) $st(mtime)]]
}

##
# Returns true if the RFC 2616 Entity Tag specified in `$etag` matches the
# Entity Tag of the current file.
#
::oo::define ::tanzer::file method entityMatches {etag} {
    if {[regexp {^"([^\"]+)"$} $etag {} quoted]} {
        set etag $quoted
    }

    return [expr {$etag eq "*" || $etag eq [my etag]}]
}

##
# Returns true if the current file modification time matches the RFC 2616
# timestamp provided in `$rfc2616`.
#
::oo::define ::tanzer::file method entityNewerThan {rfc2616} {
    my variable st

    set date  [::tanzer::date scan  $rfc2616]
    set epoch [::tanzer::date epoch $date]

    return [expr {$st(mtime) > $epoch}]
}

##
# Returns false if the ::tanzer::request object in `$request` lists an
# `If-Match:` header value that does not match the RFC 2616 Entity Tag of the
# current file.  Otherwise, returns true.
#
::oo::define ::tanzer::file method match {request} {
    if {![$request headerExists If-Match]} {
        return 1
    }

    return [my entityMatches [$request header If-Match]]
}

##
# Returns false if the ::tanzer::request object in `$request` lists an
# `If-None-Match:` header value that matches the RFC 2616 Entity Tag of the
# current file.  Otherwise, return true.
#
::oo::define ::tanzer::file method noneMatch {request} {
    if {![$request headerExists If-None-Match]} {
        return 1
    }

    return [expr {![my entityMatches [$request header If-None-Match]]}]
}

##
# Returns false if the ::tanzer::request object in `$request` lists an
# `If-Modified-Since:` header value that is newer than the modification time of
# the current file.  Otherwise, returns true.
#
::oo::define ::tanzer::file method modifiedSince {request} {
    if {![$request headerExists If-Modified-Since]} {
        return 1
    }

    return [my entityNewerThan [$request header If-Modified-Since]]
}

##
# Returns false if the ::tanzer::request object in `$request` lists an
# `If-Unmodified-Since:` header value that is older than the modification time
# of the current file.  Otherwise, returns true.
#
::oo::define ::tanzer::file method unmodifiedSince {request} {
    if {![$request headerExists If-Unmodified-Since]} {
        return 1
    }

    return [expr {![my entityNewerThan [$request header If-Unmodified-Since]]}]
}

::oo::define ::tanzer::file method mismatched {} {
    return 0
}

##
# Used as a callback for `write` events generated by `[chan event]` on a client
# channel.  Calls ::tanzer::session::pipe to shuffle data from the file handle
# to the client socket.
#
::oo::define ::tanzer::file method stream {event session} {
    my variable fh

    set sock [$session sock]

    foreach event {readable writable} {
        chan event $sock $event {}
    }

    chan copy $fh $sock -command [list apply {
        {session copied args} {
            if {[llength $args] > 0} {
                $session error [lindex $args 0]

                return
            }

            $session nextRequest
        }
    } $session]

    return
}

##
# Generate and return a `[dict]` of headers suitable for creating a response
# to serve the current file.
#
::oo::define ::tanzer::file method headers {} {
    my variable st

    set date      [::tanzer::date new $st(mtime)]
    set timestamp [::tanzer::date rfc2616 $date]

    return [dict create                \
        Content-Type   [my mimeType]   \
        Content-Length $st(size)       \
        Etag           "\"[my etag]\"" \
        Accept-Ranges  "bytes"         \
        Last-Modified  $timestamp]
}
