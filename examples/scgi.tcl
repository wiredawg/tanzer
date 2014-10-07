#! /usr/bin/env tclsh8.5

package require tanzer
package require tanzer::scgi
package require tanzer::response
package require tanzer::file::handler

::tanzer::server create server {
    port  1337
    proto "scgi"
}

server route * /* xantronix.net [::tanzer::file::handler new {
    root     /var/www/xantronix.net/doc
    static   /var/www/xantronix.net/doc
    listings 1
}] respond

server listen
vwait forever
