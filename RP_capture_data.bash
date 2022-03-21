#!/bin/bash

RUN_FOR=300
DD=`date +'%Y-%m-%d-%H-%M'`

RDIR=/root/pcap/$DD
IF_IN=eth1
IF_OUT=eth0

mkdir -p $RDIR

timeout $RUN_FOR tcpdump -nnn -i $IF_OUT -s 256 -w $RDIR/$IF_OUT.pcap udp and portrange 10000-20000 &
timeout $RUN_FOR tcpdump -nnn -i $IF_IN -s 256 -w $RDIR/$IF_IN.pcap udp and portrange 47000-51000 &

echo "1" > /proc/sys/net/netfilter/nf_conntrack_acct

for i in {1..300}
do
        ethtool -S $IF_OUT > $RDIR/$IF_OUT.$i.ethtool
        ethtool -S $IF_IN > $RDIR/$IF_IN.$i.ethtool
        tc -s filter show dev $IF_OUT root > $RDIR/$IF_OUT.tc.$i
        tc -s filter show dev $IF_IN root > $RDIR/$IF_IN.tc.$i
        conntrack -L -o extended > $RDIR/contrack.$i
        sleep 1
done

echo "0" > /proc/sys/net/netfilter/nf_conntrack_acct

