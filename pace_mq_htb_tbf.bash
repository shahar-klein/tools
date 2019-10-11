#!/bin/bash

# Given a set of ongoing sessions, identified by unique source port number,
# we can pace packets at a specified rate for a given session.
# We use a combination of:
#	mq (for distribution among core/Tx queue)
#	htb (for classification among different sessions/ports)
#	tbf 
# The script *removes* any existing TC qdisc before setup. It assumes
# that mq creates 8 qdisc (i.e. there are 8 TX queues), for each qdisc
# we create a HTB root, and for each HTb class, we create an FQ, so:
#
# mq -->	1	...			8
#	        |		 		|
#	      htb1	..		      htb8
#              |			       |
#      +---------------+		+---------------+
#      |    ...        |		| ....		|
#   sport X       sport Y	     sport X	     sport Y
#
# We create a class/filter for a session/port on HTBs on each mq disc
# because we don't know which mq will end up processing the packet,
# so it need to match a class no matter which mq it lands on.
#
# We have deep queue length to not drop packts, need to tune it based
# on experience.
#
# We don't burst currently, need to also get some experince for this.
#
# We allow about 30% more than configured rate, need to check how to
# tune this.
#
# TODOS:
# When we add more than 15 ports, we see the CPU utilization spikes, so
# better to keep the number of sessions paced around 10.
#
# Currently, we just delete all the TC cofiguration, need to provide a
# way to delete a specific session/port
#
# Add a way to show the stats for specific sessions
#
# Revisit ceil rate, burst and queue length.
#

set -u

RATE=20
RATE=${4:-${RATE}}
if [ $1 = "-h" -o $1 = "--help" ] ; then
	echo 
	echo
	echo "Usage: $0 [setup|add|delall] device sport <rate in mbit/sec>"
	echo "       # Default rate is ${RATE}mbit"
	echo "       # Example: $0 add enp5s0 3333 25mbit"
	echo
	exit 0
fi

ACT=${1:?Missing ACT: setup or add or delall}
DEV=${2:?Missing Device to configure}
if [ $ACT = delall ] ; then
	tc qdisc del dev $DEV root &>-
	exit 0
fi

ROOT_CLASS=1234
setup () {
	# Clean everything
	tc qdisc del dev $DEV root  2>/dev/null

	# Create the root qdisc etc.
	tc qdisc add dev ${DEV} root handle ${ROOT_CLASS}: mq

	for i in {1..8}
	do
		tc qd add dev ${DEV} parent ${ROOT_CLASS}:$i handle $i htb default $i
		tc class add dev ${DEV} parent $i: classid $i:$i htb rate 8gbit  ceil 10gbit mtu 1500
		tc qdisc add dev ${DEV} parent $i:$i sfq perturb 10
	done
}

if [ $ACT = setup ] ; then
	setup
	exit 0
fi

SPORT=${3:?Missing sport}
LIMIT=10
MTU=1500

# queue about 10x the rate, fairly conservative to avoid packet drops.
rateinbits=$((RATE*1000000))
rateinbytes=$((rateinbits/8))
pps=$((rateinbytes/MTU))
queue_limit=$((10*pps))
queue_limit_bytes=$((queue_limit*1500))

ceilpercent=30
ceilrate=$((rateinbits*ceilpercent/100))
ceilrate=$((rateinbits+ceilrate))

add() {
	for parent in {1..8}
	do
		CLASS_ID=${parent}:${SPORT}
		tc class add dev ${DEV}  parent $parent: classid ${CLASS_ID}  htb rate ${RATE}mbit ceil ${ceilrate} mtu $MTU
		tc qdisc add dev ${DEV} parent ${CLASS_ID}  tbf rate ${RATE}mbit burst 20000 limit ${queue_limit_bytes}
		tc filter add dev ${DEV} parent $parent:  u32 match ip sport ${SPORT} 0xffff classid ${CLASS_ID}
	done
}


if [ $ACT = setup ] ; then
	setup
	exit 0
fi
if [ $ACT = add ] ; then
	add
	exit 0
fi
if [ $ACT = delall ] ; then
	delall
	exit 0
fi

echo "Dont know what to do with: $@"
