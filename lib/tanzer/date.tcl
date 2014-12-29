package provide tanzer::date 0.1

##
# @file tanzer/date.tcl
#
# Functions for parsing and generating RFC 2616 timestamps
#

##
# Date, time and calendar facilities and constants
#
namespace eval ::tanzer::date {
    ##
    # A mapping of ASCII month names to numbers.
    #
    variable months [dict create \
        Jan  1 Feb  2 Mar  3     \
        Apr  4 May  5 Jun  6     \
        Jul  7 Aug  8 Sep  9     \
        Oct 10 Nov 11 Dec 12]

    ##
    # A positional listing of ASCII month names.
    #
    variable monthNames {
        {} Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec
    }

    ##
    # A positional listing of the number of days in each month.
    #
    variable monthLengths {
           {}
        31 28 31
        30 31 30
        31 31 30
        31 30 31
    }

    ##
    # A positional listing of the days of the week.
    #
    variable weekdays [list Sun Mon Tue Wed Thu Fri Sat]

    namespace ensemble create
    namespace export   leapYear dayOfYear new scan epoch rfc2616
}

##
# Returns true if `$year` is a leap year.
#
proc ::tanzer::date::leapYear {year} {
    if {$year % 4} {
        return 0
    }

    return [expr {$year % 100 || $year % 400 == 0}]
}

##
# Returns the number of days (starting with 1) into the year of the date object
# provided in `$date`.
#
proc ::tanzer::date::dayOfYear {date} {
    set ret 0

    dict with date {
        set leap [::tanzer::date::leapYear $year]

        for {set i 1} {$i < $month} {incr i} {
            if {$i == 2 && $leap} {
                incr ret
            }

            incr ret [lindex $::tanzer::date::monthLengths $i]
        }

        incr ret $day
    }

    return $ret
}

##
# Given a Unix epoch timestamp in `$epoch`, return a new `[dict]` containing
# the following elements:
#
# * `year`
#
# * `month`
#
# * `day`
#
# * `weekday`
#
#   A short string representation of the current day of week; one of the
#   following:
#
#   * Sun
#
#   * Mon
#
#   * Tue
#
#   * Wed
#
#   * Thu
#
#   * Fri
#
#   * Sat
#   .
#
# * `hour`
#
# * `minute`
#
# * `second`
# .
#
proc ::tanzer::date::new {epoch} {
    set firstdow    4
    set year     1969
    set leap        0
    set daylen  86400
    set hourlen  3600
    set yeardays  365
    set yearlen [expr {$yeardays * $daylen}]

    for {set n 0} {$n < $epoch} {incr n $yearlen} {
        incr year
        incr firstdow

        set leap [::tanzer::date::leapYear $year]

        if {$leap} {
            set yeardays 366

            incr n $daylen
            incr firstdow
        } else {
            set yeardays 365
        }

        set firstdow [expr {$firstdow % 7}]
    }

    set monthLengths $::tanzer::date::monthLengths

    if {$leap} {
        lset monthLengths 3 29
    }

    set yearsec   [expr {$n - $epoch}]
    set dayOfYear [expr {$yeardays - ($yearsec / $daylen)}]

    set daysec    [expr {$yearsec % $daylen}]
    set hour      [expr {23        - ($daysec / 3600)}]
    set hoursec   [expr {3600      - ($daysec % 3600)}]
    set minute    [expr {$hoursec / 60}]
    set second    [expr {$hoursec % 60}]
    set dayOfWeek [expr {($dayOfYear - $firstdow - 1) % 7}]

    set day   $dayOfYear
    set month 1

    foreach monthLength $monthLengths {
        if {$monthLength eq {}} {
            continue
        }

        if {$day <= $monthLength} {
            break
        }

        incr day -$monthLength
        incr month
    }

    return [dict create \
        year    $year   \
        month   $month  \
        day     $day    \
        hour    $hour   \
        minute  $minute \
        second  $second \
        weekday [lindex $::tanzer::date::weekdays $dayOfWeek]]
}

##
# Given an RFC 2616 timestamp in `$timestamp`, return a new date object as per
# ::tanzer::date::new.
#
proc ::tanzer::date::scan {timestamp} {
    set patterns {
        {%3s, %02d %3s %04d %02d:%02d:%02d GMT} {
            weekday day monthName year hour minute second
        }

        {%3s %3s %02d %02d:%02d:%02d %04d} {
            weekday monthName day hour minute second year
        }
    }

    foreach {pattern matchvars} $patterns {
        set expected [llength $matchvars]

        if {[::scan $timestamp $pattern {*}$matchvars] != $expected} {
            continue
        }

        set month [dict get $::tanzer::date::months $monthName]

        return [dict create \
            year    $year   \
            month   $month  \
            day     $day    \
            hour    $hour   \
            minute  $minute \
            second  $second \
            weekday $weekday]
    }

    error "Invalid timestamp"
}

##
# Given the date object in `$date`, generate an RFC 2616 timestamp string.
#
proc ::tanzer::date::rfc2616 {date} {
    return [dict with date {
        format "%s, %02d %s %04d %02d:%02d:%02d GMT" \
            $weekday $day [lindex $::tanzer::date::monthNames $month] \
            $year $hour $minute $second
    }]
}

##
# Given the date object in `$date`, generate a Unix epoch timestamp.
#
proc ::tanzer::date::epoch {date} {
    set dayOfYear [expr {[::tanzer::date::dayOfYear $date] - 1}]

    return [dict with date {
        set tm_year [expr {$year - 1900}]

        expr {
            $second + $minute * 60 + $hour * 3600 + $dayOfYear * 86400 +
                ($tm_year - 70) * 31536000 + (($tm_year - 69) / 4) * 86400 -
                (($tm_year - 1) / 100) * 86400 + (($tm_year + 299) / 400) * 86400
        }
    }]
}
