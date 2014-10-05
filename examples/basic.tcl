#! /usr/bin/env tclsh8.5

package require tanzer
package require tanzer::scgi
package require tanzer::response
package require tanzer::file::handler

namespace eval ::lambda {
    variable id 0

    proc name {} {
        variable id

        return "::lambda::lambda-[incr id]"
    }

    proc create {params body} {
        set setters {}

        foreach {key} [uplevel 1 info locals] {
            lappend setters [list set $key [uplevel 1 set $key]]
        }

        set i 0

        if {$params ne {args}} {
            foreach param $params {
                set fetch [concat {lindex $args} $i]

                lappend setters [format {
                    set {%s} [lindex $args %d]
                } $param $i]

                incr i
            }
        }

        set name [name]

        proc $name {args} [join [
            list {*}$setters $body] "\n"]

        return $name
    }

    proc destroy {lambda} {
        rename $lambda ""
    }
}

::tanzer::server create server {
    port  1337
    proto "scgi"
}

server route GET /* [::tanzer::file::handler new {
    root     /var/www/xantronix.net/doc
    static   /var/www/xantronix.net/doc
    listings 1
}] respond

server listen
vwait forever
