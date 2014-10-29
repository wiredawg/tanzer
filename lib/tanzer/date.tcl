package provide tanzer::date 0.1

##
# @file tanzer/date.tcl
#
# Functions for parsing and generating RFC 2616 timestamps
#

##
# Parse and generate RFC 2616 timestamps.
#
namespace eval ::tanzer::date {
   variable rfc2616Format "%a, %d %b %Y %T %Z"
}

##
# Transform a timestamp in seconds since the Unix epoch, provided in `$epoch`,
# to an RFC 2616 format timestamp.
#
proc ::tanzer::date::rfc2616 {epoch} {
    return [clock format $epoch -format $::tanzer::date::rfc2616Format -gmt 1]
}

##
# Transform an RFC 2616 timestamp as provided in `$rfc2616` to seconds since
# the Unix epoch.
#
proc ::tanzer::date::epoch {rfc2616} {
    return [clock scan $rfc2616 -format $::tanzer::date::rfc2616Format]
}
