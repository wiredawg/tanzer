#! /usr/bin/env tclsh8.6

package require tanzer
package require tanzer::scgi::handler

proc usage {} {
    puts stderr "usage: $::argv0 listenport scgihost scgiport"
    exit 1
}

if {$argc != 3} {
    usage
}

lassign $argv listenport scgihost scgiport

set server [::tanzer::server new]

$server route GET /* {.*} [::tanzer::scgi::handler new [list \
    host $scgihost \
    port $scgiport \
    name "/"   \
]]

set listener [socket -server [list $server accept] $listenport]
vwait forever
