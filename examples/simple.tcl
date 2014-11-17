#! /usr/bin/env tclsh8.6

package require tanzer

proc simpleResponder {event session {data ""}} {
    switch -- $event "read" {
        #
        # This is executed every time there is data that has just been read
        # from the client.  In fact, the data will be present in $data at this
        # point, as the session object handles data buffering for you, by
        # necessity, as it abstracts the act of parsing multiple requests in
        # a single HTTP/1.1 keep-alive session.
        #
        # In this example, we'll just do nothing with any data we've received.
        #
        return
    } "write" {
        #
        # This is executed every time the session socket is ready to be written
        # to.  We will make our response as brief as possible, by creating a
        # response object, buffering some data in it, and sending the entire
        # response in one single action.  Note that we can define headers
        # inline while creating the response object, but we can set them later,
        # too.
        #
        set response [::tanzer::response new 200 {
            Content-Type "text/plain"
        }]

        $response header X-Foo "bar"

        #
        # Since we're buffering the response body in the response object itself,
        # we don't have to keep track of how much we're going to write; also,
        # the Content-Length header will be automatically generated and sent
        # for us.  If one does not use [$response buffer], though, then one must
        # do this on their own.
        #
        $response buffer "Hello, world!"

        #
        # Time to send the entire response away!
        #
        $session send $response

        #
        # Now, we must yield the session to the next request.  If we wanted to
        # simply close the connection, we could do [$session destroy] instead.
        # All the appropriate cleanup would happen, as the session destructor
        # will notify the server of its demise.
        #
        $session nextRequest
    }
}

set server [::tanzer::server new]

$server route GET /* {.*:8080} simpleResponder

set listener [socket -server [list $server accept] 8080]
vwait forever
