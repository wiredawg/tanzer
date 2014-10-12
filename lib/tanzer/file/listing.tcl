package provide tanzer::file::listing 0.0.1
package require tanzer::response
package require tanzer::date
package require tanzer::uri
package require TclOO
package require Tclx

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
                }

                table.tanzer-listing {
                    border: 1px solid #d0d0d0;
                }

                table.tanzer-listing th {
                    background-color: #c0c0c0;
                }

                table.tanzer-listing tr.tanzer-file-odd {
                    background-color: #d0d0d0;
                }

                table.tanzer-listing tr.tanzer-file-even {
                    background-color: #e0e0e0;
                }
            </style>
        </head>
        <body>
        <h1>Directory listing for @dir</h1>
        <table class="tanzer-listing" width="75%">
            <tr>
                <th width="5%">Type</th>
                <th width="85%">Name</th>
                <th width="10%">Size</th>
            </tr>
    }]

    set odd 1

    array set rowClasses {
        0 "tanzer-file-even"
        1 "tanzer-file-odd"
    }

    foreach item [readdir $dir] {
        set path "$dir/$item"

        file stat $path itemSt

        my buffer [string map [list \
            @type  $itemSt(type) \
            @name  $item \
            @size  $itemSt(size) \
            @class $rowClasses($odd) \
            @uri   "[::tanzer::uri::text \
                [concat [$request path] [list $item]]]" \
        ] {
            <tr class="@class">
                <td>@type</td>
                <td><a href="@uri">@name</a></td>
                <td>@size</td>
            </tr>
        }]

        if {$odd} {
            set odd 0
        } else {
            set odd 1
        }
    }

    my buffer {
        </table>
        </body>
        </html>
    }
}
