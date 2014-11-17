#! /usr/bin/env tclsh8.6

package require tanzer
package require tanzer::cgi::handler

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

$server route {.*} /env/* {.*} [::tanzer::cgi::handler new {
    program "/var/www/xantronix.net/doc/env.cgi"
    name    "/env"
    root    "/var/www/xantronix.net/doc"
}]

$server route {.*} /* {.*} [::tanzer::file::handler new [list \
    root     $root \
    listings 1 \
]]

set listener [socket -server [list $server accept] $port]
vwait forever
