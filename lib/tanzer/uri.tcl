package provide tanzer::uri 0.1

namespace eval ::tanzer::uri {}

proc ::tanzer::uri::encode {text} {
    set utfText [encoding convertto utf-8 $text]
    set search  {[^-A-Za-z0-9._~\n]}
    set replace {%[format "%02X" [scan "\\\0" "%c"]]}

    return [string map {"\n" "%0A"} [subst \
        [regsub -all $search $utfText $replace]]]
}

proc ::tanzer::uri::decode {text} {
    set specialCases [dict create \
        "\[" "%5B" \
        "\]" "%5D"]

    set search  {%([0-9A-F]{2})}
    set replace {[format "%c" [scan "\1" "%2x"]]}

    set modified [regsub -all -nocase $search \
        [string map $specialCases $text] $replace]

    return [encoding convertfrom utf-8 [subst \
        -nobackslash -novariable $modified]]
}

proc ::tanzer::uri::filter {parts} {
    set count [llength $parts]
    set ret   [list]

    for {set i 0} {$i < $count} {incr i} {
        set part [lindex $parts $i]

        if {$part eq ".."} {
            set ret [lreplace $ret end end]
        } elseif {$part ne {} || $i == 0 || $i == $count - 1} {
            lappend ret $part
        }
    }

    return $ret
}

proc ::tanzer::uri::split {uri} {
    return [::tanzer::uri::filter [::split $uri "/"]]
}

proc ::tanzer::uri::join {parts} {
    return [::join $parts "/"]
}

proc ::tanzer::uri::parts {uri} {
    set out [list]

    foreach part [::tanzer::uri::split $uri] {
        lappend out [::tanzer::uri::decode $part]
    }

    return $out
}

proc ::tanzer::uri::text {parts} {
    set out [list]

    foreach part [::tanzer::uri::filter $parts] {
        lappend out [::tanzer::uri::encode $part]
    }

    return [::tanzer::uri::join $out]
}

proc ::tanzer::uri::up {parts} {
    set filtered [::tanzer::uri::filter $parts]
    set last     [expr {[llength $filtered] - 1}]

    if {$last == 0} {
        set part [lindex $filtered 0]

        switch -- $part {} {
            return {{} {}}
        } default {
            return $part
        }
    }

    if {[lindex $filtered end] eq {}} {
        incr last -2
    } else {
        incr last -1
    }

    return [concat [lrange $filtered 0 $last] [list {}]]
}
