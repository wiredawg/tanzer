#! /usr/bin/env tclsh8.6

package require tanzer

set ::ourPage "<html>
    <body>
        <form method=\"POST\">
            <input type=\"text\" name=\"textfield\" />
            <input type=\"submit\" />
        </form>
    </body>
</html>"

proc postResponder {event session {data ""}} {
    switch -- $event "read" {
        # In this example, we'll store the data in the session
        $session store data $data
        return
    } "write" {
        set response [::tanzer::response new 200 {
            Content-Type "text/plain"
        }]
        $response buffer [$session store data]
        $session send $response
        $session nextRequest
    }
}
proc simpleResponder {event session {data ""}} {
    switch -- $event "read" {
        return
    } "write" {
        set response [::tanzer::response new 200 {
            Content-Type "text/html"
        }]

        $response buffer $::ourPage
        $session send $response
        $session nextRequest
    }
}

set server [::tanzer::server new]

$server route GET /*  {.*:8080} simpleResponder
$server route POST /* {.*:8080} postResponder

set listener [socket -server [list $server accept] 8080]
vwait forever
