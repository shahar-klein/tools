#!/bin/bash

set -u

if [ $1 = "-h" -o $1 = "--help" ] ; then
	echo 
	echo
	echo "Usage: $0 [add|delete] device sport <rate>"
	echo "       # Default rate is 20mb"
	echo "       # Example: $0 add enp4s0 3333 25mb"
	echo
	exit 0
fi

ACT=${1:?Missing ACT: add or del}
DEV=${2:?Missing Device to configure}
SPORT=${3:?Missing sport}
RATE=${4:-20mbit}


add() {

	#init prio
	tc qdisc show dev enp5s0 | grep -q prio
	if [ $? -ne 0 ] ; then
		tc qdisc add dev $DEV root handle 1: prio bands 16
	fi
	
	
	HANDLE=`tc qdisc show  dev $DEV |  cut -d" " -f3 | cut -d":" -f1 | sort -nu | tail -1`
	HANDLE=$((HANDLE+1))
	tc qdisc show  dev $DEV | grep -q tbf
	if [ $? -ne 0 ] ; then
		i=1
	else
		i=`tc qdisc show  dev $DEV | grep tbf |  cut -d" " -f5 | cut -d":" -f2 | sort -nu | tail -1`
		i=$((i+1))
	fi
	# echo $sport,$i,$handle,
	tc qdisc add dev $DEV parent 1:${i} handle ${HANDLE}: tbf rate ${RATE} burst 100k latency 5s
	tc filter add dev $DEV protocol ip parent 1:0 prio ${i} u32 match ip sport $SPORT 0xffff flowid 1:${i}

}

del () {
	echo del
	#HEXPORT==`echo "obase=16;3336" | bc`
}

if [ $ACT = add ] ; then
	add
	exit 0
fi
if [ $ACT = del ] ; then
	del
	exit 0
fi

echo "Dont know what to do with: $@"



