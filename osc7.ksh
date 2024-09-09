# -*- mode: shell-script -*-

# SPDX-License-Identifier: Apache-2.0
# Copyright 2024 Macon Gambill

function osc7_path {
    typeset -r osc7_ok="][:alnum:][:blank:][_/?.'\"\`~@\$^*(){}|<>;:+=-"
    if [[ "${1:-}" == *[!"$osc7_ok"]* ]]; then
        typeset -r ok="${1%%[!$osc7_ok]*}"
        echo -En "$ok"
        osc7_encode "${1##+([$osc7_ok])}"
    else
        echo -En "${1:-}"
    fi
}

function osc7_int_to_hexescape {
    typeset -i16 -ur h="${1:?}"
    typeset -r e="${h#???}"
    if [[ "${#e}" -eq 1 ]]; then
	echo -En "%0$e"
    else
	echo -En "%$e"
    fi
}

function osc7_encode {
    typeset -r octals="$(echo -En "${1:-}" | /usr/bin/vis -a -o)"
    typeset -r IFS=\\
    typeset -i null=0
    for o in ${octals#\\}; do
        # vis(1) doesn't have an option to produce an octal code for a
        # backslash character.  Instead, it doubles the backslash.
        if [[ -z "$o" ]]; then
            if [[ "$null" -eq 1 ]]; then
        	echo -En %5C
                let null--
            else
        	let null++
        	continue
            fi
        else
            typeset -i8 i="8#$o"
            if [[ $i -ne 10 ]] && [[ $i -lt 39 || $i -eq 92 || $i -eq 127 ]]; then
                # exclude newline; match ASCII control characters and backslash
                osc7_int_to_hexescape "$i"
            else
                print -n "\0${i#??}"
            fi
        fi
    done
}
