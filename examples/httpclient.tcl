#! /usr/bin/env tclsh8.6

package require tanzer
package require tanzer::http::handler

set server [::tanzer::server new]

$server route GET /* {.*} [::tanzer::http::handler new {
    host "localhost"
    port 80
}]

set listener [socket -server [list $server accept] 8080]
vwait forever
