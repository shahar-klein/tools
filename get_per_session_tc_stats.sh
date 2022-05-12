#!/bin/bash


tc -s filter show dev $1 root | grep -A 36 "filter protocol ip pref 1 flower chain 6 handle" | egrep 'filter protocol ip.|Sent software|Sent hardware|src_port' | sed 's|bytes||; s|pkt||; s|src_port||; /filter protocol/c\aaa' | tr -s ' ' | sed 's|none|:0| ; s|Sent software||; s|Sent hardware||' | tr '\r\n' ' ' | sed 's|aaa|\n|g' | tr -s  ' ' | awk 'NF {printf "port %s: sw bytes:%d sw pkts:%d hw bytes:%d hw packets:%d\n", $1, $2, $3, $4, $5}'
