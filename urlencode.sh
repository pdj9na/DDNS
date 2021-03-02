#!/bin/bash

urlencode() {
    # urlencode <string>
    local out="" c
    while read -n1 c
	do
        case $c in
            [a-zA-Z0-9._-]) out="$out$c" ;;
            *) out="$out`printf '%%%02X' "'$c"`" ;;
        esac
    done
    echo -n $out
}

echo -n "$1" | urlencode
