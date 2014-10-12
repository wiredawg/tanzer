package provide tanzer::file::listing 0.0.1
package require tanzer::response
package require tanzer::date
package require tanzer::uri
package require TclOO
package require Tclx

namespace eval ::tanzer::file::listing {
    variable typeRanks [dict create {*}{
        "directory"        0
        "file"             1
        "socket"           2
        "characterSpecial" 3
        "blockSpecial"     4
        "fifo"             5
        "link"             6
    }]
}

proc ::tanzer::file::listing::humanSize {bytes} {
    if {$bytes < 1024} {
        return $bytes
    } elseif {$bytes >= 1024 && $bytes < 1048576} {
        return [format "%dKB" [expr {$bytes / 1024}]]
    } elseif {$bytes >= 1048576 && $bytes < 1073741824} {
        return [format "%dMB" [expr {$bytes / 1048576}]]
    } elseif {$bytes >= 1073741824} {
        return [format "%dGB" [expr {$bytes / 1073741824}]]
    }
}

proc ::tanzer::file::listing::compareTypes {a b} {
    set rankA [dict get $::tanzer::file::listing::typeRanks $a]
    set rankB [dict get $::tanzer::file::listing::typeRanks $b]

    if {$rankA > $rankB} {
        return 1
    } elseif {$rankA < $rankB} {
        return -1
    }

    return 0
}

proc ::tanzer::file::listing::compare {a b} {
    set itemA [lindex $a 0]
    set itemB [lindex $b 0]
    set typeA [dict get [lindex $a 1] type]
    set typeB [dict get [lindex $b 1] type]

    switch -- [::tanzer::file::listing::compareTypes $typeA $typeB] -1 {
        return -1
    } 0 {
        return [string compare $itemA $itemB]
    } 1 {
        return 1
    }

    return 0
}

proc ::tanzer::file::listing::items {dir} {
    set items [list]

    foreach item [readdir $dir] {
        set path "$dir/$item"
        file stat $path itemSt

        lappend items [list $item [array get itemSt]]
    }

    return [lsort -command ::tanzer::file::listing::compare $items]
}

::oo::class create ::tanzer::file::listing {
    superclass ::tanzer::response
}

::oo::define ::tanzer::file::listing constructor {request dir st} {
    next 200 [list \
        Content-Type  "text/html" \
        Last-Modified [::tanzer::date::rfc2616 [dict get $st mtime]]]

    #
    # If the client simply wants to determine whether or not to invalidate a
    # cache, accept a HEAD request.  If a HEAD request is given, then do not
    # create and buffer a response.
    #
    if {[$request method] eq "HEAD"} {
        return
    }

    my buffer [string map [list \
        @dir [::tanzer::uri::text [$request path]] \
    ] {
        <html>
        <head>
            <title>Directory listing for @dir</title>
            <style type="text/css">
                body {
                    font-family: "HelveticaNeue-Light", "Helvetica Neue", Helvetica;
                    background: #ffffff;
                    color: #4a4a4a;
                    margin: 0px;
                }

                a:link {
                    text-decoration: none;
                    color: #94d487;
                }

                a:visited {
                    text-decoration: none;
                    color: #d484c4;
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

                div.tanzer-footer {
                    width: 75%;
                    padding: 8px;
                    margin-top: 8px;
                    margin-left: auto;
                    margin-right: auto;
                }

                table.tanzer-listing {
                    border: 0px;
                    border-radius: 4px;
                    width: 75%;
                    padding: 0px;
                    margin-left: auto;
                    margin-right: auto;
                    border-spacing: 0 4px;
                    border-collapse: separate;
                }

                table.tanzer-listing th {
                    background-color: #f0f0f0;
                    text-align: left;
                }

                table.tanzer-listing tr.tanzer-file-odd {
                    background-color: #fafafa;
                }

                table.tanzer-listing tr.tanzer-file-even {
                    background-color: #f0f0f0;
                }

                table.tanzer-listing th,td {
                    padding: 6px;
                }
            </style>
        </head>
        <body>
        <div class="tanzer-header">Directory listing for @dir</div>
        <table class="tanzer-listing">
            <tr>
                <th width="5%">Type</th>
                <th width="5%">Size</th>
                <th width="55%">Name</th>
                <th width="25%">Date</th>
            </tr>
    }]

    set odd 1

    array set rowClasses {
        0 "tanzer-file-even"
        1 "tanzer-file-odd"
    }

    foreach item [::tanzer::file::listing::items $dir] {
        set name   [lindex $item 0]
        set itemSt [lindex $item 1]
        set path   [concat [$request path] [list $name]]
        set type   [string toupper [dict get $itemSt type] 0 0]
        set size   [dict get $itemSt size]

        if {[dict get $itemSt type] eq "directory"} {
            append  name "/"
            lappend path {}
        }

        my buffer [string map [list \
            @type  $type \
            @size  [::tanzer::file::listing::humanSize $size] \
            @name  $name \
            @date  [::tanzer::date::rfc2616 [dict get $itemSt mtime]] \
            @class $rowClasses($odd) \
            @uri   [::tanzer::uri::text $path] \
        ] {
            <tr class="@class">
                <td>@type</td>
                <td>@size</td>
                <td><a href="@uri">@name</a></td>
                <td>@date</td>
            </tr>
        }]

        set odd [expr {1 - $odd}]
    }

    my buffer {
        </table>
    }

    my buffer "<div class=\"tanzer-footer\">Generated by $::tanzer::server::name/$::tanzer::server::version</div>"

    my buffer {
        <i>
        </body>
        </html>
    }
}
