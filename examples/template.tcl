#! /usr/bin/env tclsh8.6

package require tanzer
package require tanzer::file::handler
package require teaspoon

proc usage {} {
    puts stderr "usage: $::argv0 port root"
    exit 1
}

if {$argc != 2} {
    usage
}

lassign $::argv port root

set server [::tanzer::server new [list \
    port  $port \
    proto "http" \
]]

$server route {.*} /* {.*} [::tanzer::file::handler new [list \
    root     $root \
    listings 1     \
    index    {index.tsp index.html} \
    filters  {
        {.*\.tsp$} {apply {{session localPath st} {
            set template [::teaspoon open $localPath]

            $session response -new [::tanzer::response new 200 {
                Content-Type "text/html"
            }]

            $session respond

            set output [::teaspoon::output new [list $session write]]

            chan push stdout $output

            $session cleanup chan pop stdout
            $session cleanup $template destroy

            $template process $session

            $session nextRequest
        }}}
    } \
]]

set listener [socket -server [list $server accept] $port]
vwait forever
