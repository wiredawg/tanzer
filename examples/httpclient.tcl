#! /usr/bin/env tclsh8.5

package require tanzer
package require tanzer::http
package require tanzer::http::handler
package require tanzer::response

set server [::tanzer::server new {
    port  8080
    proto "http"
}]

$server route GET /* * [::tanzer::http::handler new {
    host "localhost"
    port 80
}]

$server listen
vwait forever
