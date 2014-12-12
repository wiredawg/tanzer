#! /usr/bin/env tclsh8.6

package require tanzer
package require teaspoon::handler

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
    proto "http"]]

$server route {.*} /* {.*} [::teaspoon::handler new [list \
    root     $root \
    listings 1     \
    index    {index.tsp index.html}]]

set listener [socket -server [list $server accept] $port]
vwait forever
