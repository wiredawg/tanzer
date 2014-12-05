package provide test::tanzer 0.1
package require tcltest 2.0

namespace eval ::test::tanzer {}

proc ::test::tanzer::lives {name desc body} {
    ::tcltest::test $name $desc {
        catch $body
    } 0
}

proc ::test::tanzer::dies {name desc body expected} {
    ::tcltest::test "$name-dies" $desc {
        catch $body err
    } 0

    ::tcltest::test "$name-errors" "$name dies with $expected" {
        regexp $expected $err
    } 1
}

proc ::test::tanzer::produces {name desc script data} {
    set i 0

    foreach {input expected} $data {
        ::tcltest::test "$name-[incr i]" "$desc: $input" {
            {*}$script $input
        } $expected
    }
}

proc ::test::tanzer::finish {} {
    ::tcltest::cleanupTests
}
