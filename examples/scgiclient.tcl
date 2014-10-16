#! /usr/bin/env tclsh8.5

package require tanzer
package require tanzer::http
package require tanzer::scgi::handler
package require tanzer::response

set server [::tanzer::server new {
    port  8080
    proto "http"
}]

$server route GET /* * [::tanzer::scgi::handler new {
    host "localhost"
    port 1337
    name "/"
}] respond

$server listen
vwait forever
