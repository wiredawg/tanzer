package provide tanzer::file::fragment 0.0.1
package require TclOO

namespace eval ::tanzer::file::fragment {
    variable boundary    "sxw94fa83qpa8"
    variable endBoundary "\r\n--$boundary\r\n"
}

proc ::tanzer::file::fragment::parseRangeRequest {request size mimeType} {
    set ranges      [list]
    set headerValue [$request header Range]

    if {![regexp {^bytes=(.*)$} $headerValue {} bytesRanges]} {
        ::tanzer::error throw 416 "Invalid byte range value"
    }

    foreach bytesRange [split $bytesRanges ","] {
        set min 0
        set max [expr {$size - 1}]

        if {[regexp {^(\d+)-$} $bytesRange {} start]} {
            set min $start
        } elseif {[regexp {^-(\d+)$} $bytesRange {} endOffset]} {
            set min [expr {$size - $endOffset}]
        } elseif {[regexp {^(\d+)-(\d+)$} $bytesRange {} start end]} {
            set min $start
            set max $end
        } else {
            ::tanzer::error throw 416 "Invalid byte range value"
        }

        if {$min < 0 || $min >= $size || $max >= $size || $max < 0} {
            ::tanzer::error throw 416 "Invalid byte range value"
        }

        lappend ranges [::tanzer::file::fragment new $min $max $size $mimeType]
    }

    return $ranges
}

::oo::class create ::tanzer::file::fragment

::oo::define ::tanzer::file::fragment constructor {_min _max _size _mimeType} {
    my variable min max size offset mimeType header

    set min      $_min
    set max      $_max
    set size     $_size
    set offset   $_min
    set mimeType $_mimeType
    set header   {}
}

::oo::define ::tanzer::file::fragment method contentRange {} {
    my variable min max size

    return [format "bytes %d-%d/%d" $min $max $size]
}

::oo::define ::tanzer::file::fragment method header {} {
    my variable min max size mimeType header

    if {$header ne {}} {
        return $header
    }

    set headerFormat \
        "\r\n--%s\r\nContent-Range: bytes %d-%d/%d\r\nContent-Type: %s\r\n\r\n"

    return [set header [format $headerFormat \
        $::tanzer::file::fragment::boundary $min $max $size $mimeType]]
}

::oo::define ::tanzer::file::fragment method done {} {
    my variable offset max

    return [expr {$offset >= $max}]
}

::oo::define ::tanzer::file::fragment method size {args} {
    my variable offset max

    array set opts {
        total 0
    }

    set ret [expr {1 + $max - $offset}]

    foreach arg $args {
        switch $arg {
            -total {
                set opts(total) 1
            }

            default {
                error "Invalid option $arg"
            }
        }
    }

    if {$opts(total)} {
        incr ret [string length [my header]]
    }

    return $ret
}

::oo::define ::tanzer::file::fragment method firstChunk {} {
    my variable min offset

    return [expr {$min == $offset}]
}

::oo::define ::tanzer::file::fragment method pipe {in out readBufferSize} {
    my variable min max offset

    #
    # Do nothing if the offset exceeds the range boundary.
    #
    if {$offset >= $max} {
        return 0
    }

    seek $in $offset

    set size [expr {1 + $max - $offset}]

    if {$size > $readBufferSize} {
        set size $readBufferSize
    }

    if {[fcopy $in $out -size $size] != $size} {
        error "Incomplete read"
    }

    if {[eof $in]} {
        return 0
    }

    incr offset $size

    return $size
}
