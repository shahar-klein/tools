#!/bin/bash

set -u
DEV=${1:?Missing DEV}
PORT=${2:?Missing port}
PCAP=/tmp/2.pcap

clear
echo
echo
echo


while [ 1 ] ; do
        timeout 1.5 tcpdump -ni $DEV  -q udp port $PORT --direction=out -w $PCAP >/dev/null 2>&1
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
