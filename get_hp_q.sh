#!/bin/bash

Usage() {
	echo 
	echo
	echo "Usage: $0 [ OPTIONS ] -d device"
	echo "  -H only hardware traffic"
	echo "  -M map queue to src port"
	echo
	exit $1
}
ONLY_HW=no
MAP=no

while getopts ":d:hHM" opt; do
  case ${opt} in
    H )
      ONLY_HW=yes
      ;;
    d )
      dev=$OPTARG
      ;;
    M )
      map=yes
      ;;
    h )
            Usage 0
      ;;
    \? )
            Usage 0
      ;;
    : )
            Usage 0
      ;;
    * )
            Usage 0
      ;;
  esac
done

if [ $OPTIND = 1 ] ; then 
	Usage 1 
fi
if [ -z $dev ] ; then
	echo
	echo "Error: must have device"
	Usage 2
fi

tc -s filter show dev $dev root | grep -q priority
if [ $? != 0 ] ; then
	if [[ $ONLY_HW = no ]] ; then
		tc -s filter show dev $dev root | grep -A5 mirred | egrep "software|hardware" | tr '\r\n' ' ' | awk '{printf "hp_hw_q0_bytes: %.0f\nhp_hw_q0_pkts:  %.0f\nhp_sw_q0_bytes: %.0f\nhp_sw_q0_pkts:  %.0f\n", $9, $11, $3, $5}'
	fi

	if [[ $ONLY_HW = yes ]] ; then
		tc -s filter show dev $dev root | grep -A5 mirred | egrep "software|hardware" | tr '\r\n' ' ' | awk '{printf "hp_hw_q0_bytes: %.0f\nhp_hw_q0_pkts:  %.0f\n", $9, $11}'
	fi
	exit 0
fi




#port | queue(hex) | sw bytes | sw pkts | hw bytes | hw pkts
tc -s filter show dev $dev root | egrep -A 6 'filter protocol ip.*handle|priority|src_port|mirred' | egrep 'filter protocol ip.*handle|Sent software|Sent hardware|priority|src_port' | sed 's|bytes||; s|pkt||; s|src_port||; /filter protocol/c\aaa' | tr -s ' ' | sed 's|none|:0| ; s|action order 1: skbedit priority :|| ; s|pipe||; s|Sent software||; s|Sent hardware||' | tr '\r\n' ' ' | sed 's|aaa|\n|g' | tr -s  ' ' > /tmp/CL

if [[ $map = yes ]] ; then
	awk 'NF {printf "hp_hw_q%d: %ld\n", "0x" $2, $1}' /tmp/CL
	exit 0
fi

if [[ $ONLY_HW = yes ]] ; then
	awk 'NF {printf "hp_hw_q%d_bytes: %.0f\nhp_hw_q%d_pkts:  %.0f\n", "0x" $2, $5, "0x" $2, $6}' /tmp/CL
	exit 0
fi

if [[ $ONLY_HW = no ]] ; then
	awk 'NF {printf "hp_hw_q%d_bytes: %.0f\nhp_hw_q%d_pkts:  %.0f\nhp_sw_q%d_bytes: %.0f\nhp_sw_q%d_pkts:  %.0f\n", "0x" $2, $5, "0x" $2, $6, "0x" $2, $3, "0x" $2, $4}' /tmp/CL
	exit 0
fi




