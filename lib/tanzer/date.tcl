package provide tanzer::date 0.0.1

namespace eval ::tanzer::date {}

proc ::tanzer::date::rfc2616 {epoch} {
    return [clock format $epoch -format "%a, %d %b %Y %T %Z" -gmt 1]
}
