# -*- mode: shell-script -*-

# SPDX-License-Identifier: Apache-2.0
# Copyright 2024 Macon Gambill

if [[ -z "${osc7_ok:-}" ]]; then
    readonly osc7_ok="][:alnum:][:blank:][_/?.'\"\`~@\$^*(){}|<>;:+=-"
fi

function osc7_path {
    if [[ "${1:-}" == *[!"$osc7_ok"]* ]]; then
        local -r ok="${1%%[!$osc7_ok]*}"
        echo -En "$ok"
        shopt -s extglob
        osc7_encode "${1##+([$osc7_ok])}"
    else
        echo -En "${1:-}"
    fi
}

function osc7_encode {
    local str="${1:-}"
    while [[ ${#str} -gt 0 ]]; do
	local c="${str:0:1}"
	local -i i="$(printf '%d' \'"$c")"
        if [[ $i -ne 10 ]] && [[ $i -lt 39 || $i -eq 92 || $i -eq 127 ]]; then
            # Should match ASCII control characters, newline, and backslash
	    printf %%%02X "$i"
	else
	    echo -En "$c"
	fi
	str="${str:1}"
    done
}
