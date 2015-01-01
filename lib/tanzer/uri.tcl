package provide tanzer::uri 0.1

##
# @file tanzer/uri.tcl
#
# URI parsing and manipulation
#

##
# Provides a small set of URI parsing and processing functions.
#
namespace eval ::tanzer::uri {}

##
# URI encode the data provided in `$text` and return a new string.
#
proc ::tanzer::uri::encode {text} {
    set utfText [encoding convertto utf-8 $text]
    set search  {[^-A-Za-z0-9._~\n]}
    set replace {%[format "%02X" [scan "\\\0" "%c"]]}

    return [string map {"\n" "%0A"} [subst \
        [regsub -all $search $utfText $replace]]]
}

##
# URI decode the data provided in `$text` and return a new string.
#
proc ::tanzer::uri::decode {text} {
    set parts [list]

    foreach part [::split $text "+"] {
        set specialCases [dict create \
            "\[" "%5B" \
            "\]" "%5D"]

        set search  {%([0-9A-F]{2})}
        set replace {[format "%c" [scan "\1" "%2x"]]}

        set modified [regsub -all -nocase $search \
            [string map $specialCases $part] $replace]

        lappend parts [encoding convertfrom utf-8 [subst \
            -nobackslash -novariable $modified]]
    }

    return [::join $parts " "]
}

##
# Extract parameters from the string provided in `$query`.
#
proc ::tanzer::uri::params {query} {
    set params [list]

    foreach pair [::split $query "&"] {
        #
        # Split only once, in case a value contains an equals sign for whatever
        # perverse reason.
        #
        if {[regexp {^(.*)=(.*)$} $pair {} name value]} {
            lappend params \
                [::tanzer::uri::decode $name] [::tanzer::uri::decode $value]
        }
    }

    return $params
}

##
# Filter out unnecessary items from the list of path components provided in
# `$parts`.
#
# The following modifications are made to the path:
#
# * Any `..` components are resolved to one path component level up.
#
# * Any empty components are discarded.
# .
#
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

##
# Split and filter the path components of `$uri`, returning a path copmonent
# list.
#
proc ::tanzer::uri::split {uri} {
    return [::tanzer::uri::filter [::split $uri "/"]]
}

##
# Join the path components in `$parts` into a URI string.
#
proc ::tanzer::uri::join {parts} {
    return [::join $parts "/"]
}

##
# Split `$uri` into parts, filtering out unnecessary components and URI
# decoding each along the way, returning the resulting set of path components.
#
proc ::tanzer::uri::parts {uri} {
    set out [list]

    foreach part [::tanzer::uri::split $uri] {
        lappend out [::tanzer::uri::decode $part]
    }

    return $out
}

##
# Combine the path components in `$parts`, performing URL encoding of each
# part, and return a new string.
#
proc ::tanzer::uri::text {parts} {
    set out [list]

    foreach part [::tanzer::uri::filter $parts] {
        lappend out [::tanzer::uri::encode $part]
    }

    return [::tanzer::uri::join $out]
}

##
# Determine and return the path one level up from `$parts`.
#
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
