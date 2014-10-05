package provide tanzer::file 0.0.1
package require tanzer::response

package require fileutil::magic::mimetype
package require TclOO
package require sha1

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
        -blocking    0 \
        -buffering   full \
        -buffersize  $config(readBufferSize)
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

    set mimeType [lindex [::fileutil::magic::mimetype $path] 0]

    if {$mimeType ne {}} {
        return $mimeType
    }

    switch -glob -nocase $path {
        *.txt  { return "text/plain" }
        *.htm -
        *.html { return "text/html" }
    }

    return "application/octet-stream"
}

::oo::define ::tanzer::file method etag {} {
    my variable path st

    return [::sha1::sha1 -hex [concat \
        $path $st(mtime) $st(ino)]]
}

::oo::define ::tanzer::file method stream {event session data} {
    my variable fh config

    set buf [read $fh $config(readBufferSize)]

    if {[eof $fh]} {
        $session destroy
        my destroy
        return
    }

    return [$session write $buf]
}

::oo::define ::tanzer::file method serve {session} {
    my variable config path st

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

    $response header Content-Type   [::tanzer::file::handler::mimeType $path]
    $response header Content-Length $st(size)
    $response header ETag           "\"[my etag]\""
    $response header Accept-Ranges  "bytes"
    $response header Last-Modified  [::tanzer::date::rfc2616 $st(mtime)]

    if {$method eq "GET"} {
        $session delegate [self] stream
    }

    $session send $response

    $response destroy

    #
    # Only close the session immediately if we're only sending headers.
    #
    if {$method eq "HEAD"} {
        $session destroy
    }
}
