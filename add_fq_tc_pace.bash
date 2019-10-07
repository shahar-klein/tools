#!/bin/bash

set -u

if [ $1 = "-h" -o $1 = "--help" ] ; then
	echo 
	echo
	echo "Usage: $0 [add|delete|delall] device sport <rate>"
	echo "       # Default rate is ${RATE}"
	echo "       # Example: $0 add ${DEV} 3333 25mbit"
	echo
	exit 0
fi

ACT=${1:?Missing ACT: add or del}
DEV=${2:?Missing Device to configure}
if [ $ACT = delall ] ; then
	tc qdisc del dev $DEV root &>-
	exit 0
fi
SPORT=${3:?Missing sport}
RATE=${4:-${RATE}}
FLOW_LIMIT=10000
ROOT_CLASS=1234

add() {

	tc qdisc show dev $DEV | grep -q htb
	if [ $? -ne 0 ] ; then
		tc qdisc add dev ${DEV} handle ${ROOT_CLASS}: root htb
	fi
	
	
	HANDLE=`echo "obase=16;$SPORT" | bc`
	CLASS_ID=${ROOT_CLASS}:${SPORT}
	tc class add dev ${DEV}  parent ${ROOT_CLASS}: classid ${CLASS_ID} htb rate ${RATE}
	tc qdisc add dev ${DEV} parent ${CLASS_ID}  fq maxrate ${RATE} flow_limit ${FLOW_LIMIT}
	tc filter add dev ${DEV} parent ${ROOT_CLASS}:  handle 0x${HANDLE} prio ${SPORT} u32 match ip sport ${SPORT} 0xffff classid ${CLASS_ID}
}

del () {
	echo del
	tc filter del dev $DEV prio ${SPORT}
	CLASS_ID=${ROOT_CLASS}:${SPORT}
	tc class del  dev enp4s0 classid ${CLASS_ID}
}

if [ $ACT = add ] ; then
	add
	exit 0
fi
if [ $ACT = del ] ; then
	del
	exit 0
fi
if [ $ACT = delall ] ; then
	delall
	exit 0
fi

echo "Dont know what to do with: $@"



