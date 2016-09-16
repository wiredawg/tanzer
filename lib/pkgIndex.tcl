namespace eval ::tanzer {
    variable version 0.1

    variable packages {
        tanzer
        tanzer::date
        tanzer::daemon
        tanzer::error
        tanzer::forwarder
        tanzer::logger
        tanzer::message
        tanzer::message::chunk
        tanzer::request
        tanzer::response
        tanzer::router
        tanzer::router::entry
        tanzer::session
        tanzer::server
        tanzer::uri
        tanzer::cgi
        tanzer::cgi::handler
        tanzer::file
        tanzer::file::fragment
        tanzer::file::partial
        tanzer::file::handler
        tanzer::file::listing
        tanzer::http
        tanzer::http::handler
        tanzer::http::request
        tanzer::scgi
        tanzer::scgi::handler
        tanzer::scgi::request
    }
}

foreach package $::tanzer::packages {
    set file   "[string map {:: /} $package].tcl"
    set source [list source [file join $dir $file]]

    package ifneeded $package $::tanzer::version $source
}
