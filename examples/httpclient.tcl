#! /usr/bin/env tclsh8.5

package require tanzer
package require tanzer::http
package require tanzer::http::handler
package require tanzer::response

set server [::tanzer::server new]

$server route GET /* * [::tanzer::http::handler new {
    host "localhost"
    port 80
}]

set listener [socket -server [list $server accept] 8080]
vwait forever
