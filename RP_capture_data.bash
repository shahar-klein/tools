#!/bin/bash

RUN_FOR=300
DD=`date +'%Y-%m-%d-%H-%M'`

RDIR=/root/pcap/$DD

mkdir -p $RDIR

timeout $RUN_FOR tcpdump -nnn -i eth0 -s 256 -w $RDIR/eth0.pcap udp and portrange 10000-20000 &
timeout $RUN_FOR tcpdump -nnn -i eth1 -s 256 -w $RDIR/eth1.pcap udp and portrange 47000-51000 &

echo "1" > /proc/sys/net/netfilter/nf_conntrack_acct

for i in {1..300}
do
        ethtool -S eth0 > $RDIR/eth0.$i.ethtool
        ethtool -S eth1 > $RDIR/eth1.$i.ethtool
        tc -s filter show dev eth0 root > $RDIR/eth0.tc.$i
        tc -s filter show dev eth1 root > $RDIR/eth1.tc.$i
        conntrack -L -o extended > $RDIR/contrack.$i
        sleep 1
done

echo "0" > /proc/sys/net/netfilter/nf_conntrack_acct

