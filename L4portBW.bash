#!/bin/bash

set -u

if [ $1 = "-h" -o $1 = "--help" ] ; then
	echo "Usage: $0 dev port <direction>"
	echo "Direction can be: in, out or inout(default)"
	echo "Note: You must be root to run this tool"
	exit 0
fi

U=`id -u`
if [ $U -ne 0 ] ; then
	echo "Must be root to run $0"
	exit 1
fi

DEV=${1:?Missing DEV}
PORT=${2:?Missing port}
DIRECTION=${3:-inout}
PCAP=/tmp/L4foo2.pcap


clear
echo
echo
echo


while [ 1 ] ; do
        timeout 1.5 tcpdump -ni $DEV  -q udp port $PORT --direction=$DIRECTION -w $PCAP >/dev/null 2>&1
        L=`tcpdump -nr $PCAP -ttttt --time-stamp-precision=micro -K -s 0 --number -q 2>&1 | grep -v reading | grep 00:00:00 | tail -n1 | awk '{print $1}'`
	if [ A$L = A ] ; then
		echo "Can't see port $PORT"
		sleep 1
		continue
	fi
        cmd="sed -n '1,${L}p'"
        MB=`tcpdump -nr $PCAP -ttttt --time-stamp-precision=micro -K -s 0 --number -q 2>&1 | grep -v reading | grep 00:00:00  | sed -n "1,${L}p" | grep length | awk 'BEGIN {sum=0} {sum+=$9} END {print sum*8/1000000}'`
        echo $DEV port $PORT: $MB
        echo -e "\033[2A"
        sleep 0.3
done
