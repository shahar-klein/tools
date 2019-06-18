#!/bin/bash

# 

#
# cleanup
#	clean loadr, initiator, rp ip addresses from the relevant devs
#	restart rp
#	
# setup
#	descriptive log name / maybe a dir (and throw all logs into it
#	ip setup if needed
#	rp setup
# init
#	take system readings like ethtool, drop count etc
# run in background
#	noodle
#	10 secs mpstat
#	10 secs traffic on all 3 nodes
# 
# finit
#	take system readings like ethtool, drop count etc

get_mac_dev() {
	host=$1
	dev=$2
	mac=`ssh $host ip -o link show $dev | egrep -o 'ether (.*)' | awk '{print $2}'`
	echo $mac

}


set_ip_dev() {
	host=$1
	dev=$2
	ip=$3
	ssh $host ip a add dev $dev $ip/24
	ssh $host ip link set $dev up
}


LOADER=10.0.0.147
LOADER_DEV=ens2
LOADER_IP=5.5.5.5
LOADER_DEV_MAC=`get_mac_dev $LOADER $LOADER_LOAD_DEV`
set_ip_dev $LOADER $LOADER_DEV $LOADER_IP

INITIATOR=10.0.0.148
INITIATOR_DEV=ens2
INITIATOR_IP=20.20.20.20
INITIATOR_DEV_MAC=`get_mac_dev $INITIATOR $INITIATOR_LOAD_DEV`
set_ip_dev $INITIATOR $INITIATOR_DEV $INITIATOR_IP

RP=192.168.122.5
RP_PRIV_LEG_IP=5.5.5.1
RP_PRIV_LEG_DEV=ens5
RP_PRIV_LEG_MAC=`get_mac_dev $RP $RP_PRIV_LEG_DEV`
set_ip_dev $RP $RP_PRIV_DEV $RP_PRIV_LEG_IP


RP_PUB_LEG=20.20.20.100
RP_PUB_LEG_DEV=ens6
RP_PUB_LEG_MAC=`get_mac_dev $RP $RP_PUB_LEG_DEV`
set_ip_dev $RP $RP_PUB_DEV $RP_PUB_LEG_IP

