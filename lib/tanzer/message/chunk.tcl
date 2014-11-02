package provide tanzer::message::chunk 0.1

##
# @file tanzer/message/chunk.tcl
#
# HTTP/1.1 Chunked Transfer Encoding support
#

namespace eval ::tanzer::message::chunk {
    namespace ensemble create
    namespace export   parse
}

##
# Called as `[::tanzer::message::chunk parse]`.
#
# Given the name of a buffer in the caller's context in `$varName`, and a
# chunk body handler callback specified in `$args`, parse each chunk from the
# buffer and pass it to the callback.  The buffer is trimmed after each
# successfully parsed chunk.
#
proc ::tanzer::message::chunk::parse {varName args} {
    upvar 1 $varName buffer

    set length [string length $buffer]

    while {1} {
        set headerStart 0
        set headerEnd   [expr {[string first "\r\n" $buffer] - 1}]

        #
        # If the end of the chunk description line cannot be found, then
        # continue onwards.
        #
        if {$headerEnd < 0} {
            return 1
        }

        set header  [string range $buffer $headerStart $headerEnd]
        set pattern {^([0-9a-f]+)(?:;\s*(.*))*$}

        if {[regexp -nocase $pattern $header {} bodySize extensions]} {
            scan $bodySize %x bodySize

            foreach extension [split $extensions ";"] {
                set extension [string trim $extension]
            }

            set bodyStart [expr {$headerEnd + 3}]
            set bodyEnd   [expr {$bodyStart + $bodySize - 1}]
            set chunkEnd  [expr {$bodyEnd + 2}]

            #
            # If the buffer does not have enough data to cover the current
            # chunk body size, plus ending, then move on.
            #
            if {$length - 1 < $bodyEnd} {
                return 1
            }

            #
            # Ensure the body is terminated by a CRLF sequence.
            #
            set terminator [string range $buffer \
                [expr {$bodyEnd + 1}] $chunkEnd]

            if {$terminator ne "\r\n"} {
                error "Invalid chunk terminator"
            }

            #
            # Pass the body to the callback.
            #
            if {$bodySize > 0} {
                {*}$args [string range $buffer $bodyStart $bodyEnd]
            }

            #
            # Trim the current netstring from the buffer.
            #
            set buffer [string range $buffer [expr {$chunkEnd + 1}] end]

            if {$bodySize == 0} {
                return 0
            }
        } else {
            error "Invalid chunk header '$header'"
        }
    }

    return 1
}
