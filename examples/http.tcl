#! /usr/bin/env tclsh8.5

package require tanzer
package require tanzer::http
package require tanzer::response
package require tanzer::file::handler

::tanzer::server create server {
    port  8080
    proto "http"

    logging {
        accessLog "/var/log/tanzer/access.log"
        errorLog  "/var/log/tanzer/error.log"
    }
}

server route GET /* [::tanzer::file::handler new {
    root     "/var/www/xantronix.net/doc"
    static   "/var/www/xantronix.net/doc"
    listings 1
}] respond

server listen
vwait forever
