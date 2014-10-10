#! /usr/bin/env tclsh8.5

package require tanzer
package require tanzer::http
package require tanzer::response
package require tanzer::file::handler
package require tanzer::cgi::handler

::tanzer::server create server {
    port  8080
    proto "http"
}

server route * /env.cgi xantronix.local:8080 [::tanzer::cgi::handler new {
    root    "/var/www/xantronix.net/doc"
    program "/var/www/xantronix.net/doc/env.cgi"
    name    "/env.cgi"
}] respond

server route * /* www.xantronix.local:8080 [::tanzer::file::handler new {
    root     "/var/www/xantronix.net/doc"
    static   "/var/www/xantronix.net/doc"
    listings 1
}] respond

server listen

vwait forever
