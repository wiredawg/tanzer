#! /usr/bin/env tclsh8.5

package require tanzer
package require tanzer::http
package require tanzer::file::handler
package require tanzer::cgi::handler

proc usage {} {
    puts stderr "usage: $::argv0 port root"
    exit 1
}

if {$argc != 2} {
    usage
}

set port [lindex $::argv 0]
set root [lindex $::argv 1]

set server [::tanzer::server new [list \
    port  $port \
    proto "http" \
]]

$server route {.*} /* {.*} [::tanzer::file::handler new [list \
    root     $root \
    listings 1 \
]]

$server listen
vwait forever
