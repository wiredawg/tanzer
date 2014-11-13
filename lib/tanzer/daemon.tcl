package provide tanzer::daemon 0.1
package require tanzer
package require tanzer::response
package require tanzer::file::handler
package require tanzer::cgi::handler
package require TclOO

::oo::class create ::tanzer::daemon

::oo::define ::tanzer::daemon constructor {{config {port 80 proto http}}} {
    my variable port proto server sites \
        roots listings programs aliases

    set server [::tanzer::server new [list \
        port  [dict get $config port] \
        proto [dict get $config proto]]]

    set sites [list]

    array set roots    {}
    array set listings {}
    array set programs {}
    array set aliases  {}
}

::oo::define ::tanzer::daemon method site {name config} {
    my variable server sites roots listings \
        programs aliases

    lappend sites $name

    set aliases($name)  [list]
    set programs($name) [list]
    set listings($name) 0

    foreach {command data} $config {
        switch -- $command alias {
            lappend aliases($name) $data
        } root {
            set roots($name) $data
        } cgi {
            lappend programs($name) $data
        } listings {
            set listings($name) $data
        }
    }

    return
}

::oo::define ::tanzer::daemon method config {config} {
    my variable port proto server sites \
        roots listings programs aliases
    
    foreach {command name data} $config {
        my $command $name $data
    }

    array set handlers {}
    array set routes   {}

    foreach site $sites {
        set handlers($site) [list]

        foreach program $programs($site) {
            set handler [list [::tanzer::cgi::handler new [dict create \
                root $roots($site) {*}$program]]]

            lappend handlers($site) $handler

            set routes($handler) [list {.*} "[dict get $program name]/*"]
        }

        set handler [list [::tanzer::file::handler new [dict create \
            root $roots($site) \
            listings $listings($site)]]]

        lappend handlers($site) $handler

        set routes($handler) [list {.*} /*]

        foreach domain [concat $site $aliases($site)] {
            foreach handler $handlers($site) {
                set route $routes($handler)

                $server route {*}$route $domain {*}$handler
            }
        }
    }

    return
}

::oo::define ::tanzer::daemon method server {} {
    my variable server

    return $server
}

::oo::define ::tanzer::daemon method run {} {
    my variable server

    $server listen
    vwait forever
}
