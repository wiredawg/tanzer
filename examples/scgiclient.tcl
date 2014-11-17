#! /usr/bin/env tclsh8.6

package require tanzer
package require tanzer::scgi::handler

set server [::tanzer::server new]

$server route GET /* {.*} [::tanzer::scgi::handler new {
    host "localhost"
    port 1337
    name "/"
}]

set listener [socket -server [list $server accept] 8080]
vwait forever
