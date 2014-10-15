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

proc ::tanzer::file::listing::humanTimestamp {epoch} {
    set now [clock seconds]
    set age [expr {$now - $epoch}]

    if {$age == 1} {
        return "1 second ago"
    } elseif {$age == 0 || $age < 60} {
        return [format "%d seconds ago" $age]
    } elseif {$age >= 60 && $age < 120} {
        return "About 1 minute ago"
    } elseif {$age >= 120 && $age < 3600} {
        return [format "%d minutes ago" [expr {$age / 60}]]
    } elseif {$age >= 3600 && $age < 86400} {
        return [clock format $epoch -format "%H:%M today GMT" -gmt 1]
    } elseif {$age >= 86400 && $age < 172800} {
        return [clock format $epoch -format "%H:%M yesterday GMT" -gmt 1]
    }

    return [clock format $epoch -format "%d %b %Y, %H:%M GMT" -gmt 1]
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
    set typeA [dict get $a type]
    set typeB [dict get $b type]

    switch -- [::tanzer::file::listing::compareTypes $typeA $typeB] -1 {
        return -1
    } 0 {
        set nameA [dict get $a name]
        set nameB [dict get $b name]

        return [string compare $nameA $nameB]
    } 1 {
        return 1
    }

    return 0
}

proc ::tanzer::file::listing::items {localDir path} {
    set items [list]

    foreach name [concat .. [readdir $localDir]] {
        set subpath [::tanzer::uri::filter [concat $path $name]]

        if {$subpath eq {}} {
            continue
        }

        set localPath "$localDir/$name"
        file stat $localPath itemSt

        set size [if {$itemSt(type) eq "file"} {
            ::tanzer::file::listing::humanSize $itemSt(size)
        } else {
            list
        }]

        if {$itemSt(type) eq "directory"} {
            lappend subpath {}
            append  name "/"
        }

        lappend items [list \
            type $itemSt(type) \
            size $size \
            name $name \
            date [::tanzer::file::listing::humanTimestamp $itemSt(mtime)] \
            uri  [::tanzer::uri::text $subpath]]
    }

    return [lsort -command ::tanzer::file::listing::compare $items]
}

::oo::class create ::tanzer::file::listing {
    superclass ::tanzer::response
}

::oo::define ::tanzer::file::listing constructor {request localDir st} {
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

    set path [$request path]

    my buffer [string map [list \
        @path [::tanzer::uri::text $path] \
    ] {
        <html>
        <head>
            <title>Directory listing for @path</title>
            <style type="text/css">
                body {
                    font-family: "HelveticaNeue-Light", "Helvetica Neue", Helvetica;
                    background: #ffffff;
                    color: #4a4a4a;
                    margin: 0px;
                }

                a:link {
                    text-decoration: none;
                    color: #74b467;
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
                    font-size: 10pt;
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
                }

                table.tanzer-listing th.tanzer-file-name, th.tanzer-file-date {
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

                table.tanzer-listing td.tanzer-date, table.tanzer-listing td.tanzer-size {
                    font-family: "Andale Mono", monospace;
                    white-space: nowrap;
                }

                table.tanzer-listing td.tanzer-size {
                    text-align: right;
                }
            </style>
        </head>
        <body>
        <div class="tanzer-header">Directory listing for @path</div>
        <table class="tanzer-listing">
            <tr>
                <th width="5%">Size</th>
                <th class="tanzer-file-name" width="65%">Name</th>
                <th class="tanzer-file-date" width="30%">Last Modified</th>
            </tr>
    }]

    set odd 1

    array set rowClasses {
        0 "tanzer-file-even"
        1 "tanzer-file-odd"
    }

    foreach item [::tanzer::file::listing::items $localDir $path] {
        my buffer [string map [list \
            @size  [dict get $item size] \
            @name  [dict get $item name] \
            @date  [dict get $item date] \
            @uri   [dict get $item uri] \
            @class $rowClasses($odd) \
        ] {
            <tr class="@class">
                <td class="tanzer-size">@size</td>
                <td><a href="@uri">@name</a></td>
                <td class="tanzer-date">@date</td>
            </tr>
        }]

        set odd [expr {1 - $odd}]
    }

    my buffer {
        </table>
    }

    my buffer "<div class=\"tanzer-footer\">Generated by $::tanzer::server::name/$::tanzer::server::version</div>"

    my buffer {
        </body>
        </html>
    }
}
