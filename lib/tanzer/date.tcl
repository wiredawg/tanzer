package provide tanzer::date 0.1

namespace eval ::tanzer::date {
    variable rfc2616Format "%a, %d %b %Y %T %Z"
}

proc ::tanzer::date::rfc2616 {epoch} {
    return [clock format $epoch -format $::tanzer::date::rfc2616Format -gmt 1]
}

proc ::tanzer::date::epoch {rfc2616} {
    return [clock scan $rfc2616 -format $::tanzer::date::rfc2616Format]
}
