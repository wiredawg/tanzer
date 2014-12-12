tänzer: The Lovable Web Server Framework for Tcl!
=================================================

See http://tanzer.io/ for further information.

Documentation
-------------

http://tanzer.io/doc/

What is tänzer?
---------------

tänzer is a minimalistic web server framework for Tcl which provides a very
straightforward environment for writing HTTP/1.1 web applications.

Writing asynchronous web applications shouldn't have to be complicated.
Fortunately, tänzer is there to take you on a dance journey through the perils
of keepalive requests, HTTP message parsing, and SCGI and CGI support.  Writing
"Hello, world!" with tänzer is a snap!  And so is everything else you want to
do.  Write your app with tänzer today.

Features
--------

* Asynchronous HTTP/1.1 web server

* Pattern-based request routing engine

* SCGI client and server support

* CGI executable support

* Fast static file service

* Works out-of-the-box on Tcl 8.6

Example
-------

```tcl
    package require tanzer

    set server [::tanzer::server new]

    $server route GET /* {.*:8080} apply {
        {event session args} {
            if {$event ne "write"} {
                return
            }
            
            $session response -new [::tanzer::response new 200 {
                Content-Type "text/plain"
                X-Foo        "bar"
            }]
            
            $session response buffer "Hello, world!"
            $session respond
            $session nextRequest
        }
    }

    $server listen 8080
```

Copyright
=========

Copyright (c) 2014 Alexandra Hrefna Hilmisdóttir.

License
=======

Released under the terms of the MIT license.
