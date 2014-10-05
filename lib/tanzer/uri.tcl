package provide tanzer::uri 0.0.1

namespace eval ::tanzer::uri {}

proc ::tanzer::uri::clean {parts} {
    set ret   [list]
    set count [llength $parts]

    for {set i 0} {$i < $count} {incr i} {
        set part [lindex $parts $i]

        if {$part ne {} || $i == 0 || $i == $count - 1} {
            lappend ret $part
        }
    }

    return $ret
}

proc ::tanzer::uri::parts {uri} {
    return [::tanzer::uri::clean [split $uri "/"]]
}

proc ::tanzer::uri::text {parts} {
    return [join [::tanzer::uri::clean $parts] "/"]
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
