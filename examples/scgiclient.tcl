#! /usr/bin/env tclsh8.5

package require tanzer
package require tanzer::http
package require tanzer::scgi::handler
package require tanzer::response

set server [::tanzer::server new]

$server route GET /* {.*} [::tanzer::scgi::handler new {
    host "localhost"
    port 1337
    name "/"
}]

set listener [socket -server [list $server accept] 8080]
vwait forever
