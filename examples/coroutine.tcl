#! /usr/bin/env tclsh8.6

package require tanzer
package require tanzer::file::handler

proc usage {} {
    puts stderr "usage: $::argv0 port"
    exit 1
}

if {$argc != 1} {
    usage
}

lassign $::argv port

set server [::tanzer::server new [list \
    port  $port \
    proto "http" \
]]

$server route GET /* {.*} apply {{event session {data ""}} {
    if {$event ne "write"} {
        return
    }

    set continuation "$session\::continuation"

    #
    # If a continuation for the current session exists, then call it and return
    # from the main event handler.
    #
    if {[info commands $continuation] ne {}} {
        $continuation

        return
    }

    #
    # Since there is no continuation for the current session, create one.  Each
    # point at which the continuation yields, control is of course passed back
    # to the current event handler.
    #
    # [rename] will only succeed when called by the cleanup method
    # [::tanzer::session cleanup] when dispatched by the continuation itself;
    # as, when the coroutine the continuation refers to ends, the continuation
    # ceases to exist.
    #
    coroutine $continuation apply {{session} {
        $session response -new [::tanzer::response new 200 {
            Content-Type "text/plain"
        }]

        $session respond

        yield

        $session write "Foo\n"

        yield

        $session write "Bar\n"

        yield

        $session nextRequest
    }} $session

    #
    # Notify the session handler to delete the continuation when the session
    # handler itself is ready to clean up request state.  
    #
    $session cleanup rename $continuation {}
}}

set listener [socket -server [list $server accept] $port]
vwait forever
