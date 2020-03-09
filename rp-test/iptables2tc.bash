#!/bin/bash

# Some rules might not take effect when doing this due to timing issues, esp.
# if we are converting large number of flows at the same time. Give a few mins
# for things to settle down and check if there are any such flows using:
# 	conntrack -L | grep -i unrepl | grep "dport=8"  
# note the "dport=8" is because that's the destination port range our test
# script (that initiates sessions) uses. If the above returns some sessions
# clear them using
# conntrack -L | grep -i unrepl | grep "dport=8"  | awk '{print $7}' | cut -f2 -d=  | sort -u | xargs -r -l conntrack -D -p udp --dport
# the sessions should be fine.

# Before using this script to convert ports, initialize using
# 	bash iptables2tc.bash initialize
# Convert an existing iptable rule (say for port 8000) using:
# 	bash iptables2tc.bash run 8000

echo "Make sure we have all the data before running, then delete this line and next one"
exit 1

set -e

# Track in either direction:
# From the initiator/pub to the loader/private
#	pub => zone 3 => zone 2 => priv
# From the loader/private to the initiator/pub
#	priv => zone 4 => zone 5 => pub
# At any time one of the above will be true based on which side the 1st packet
# is seen from.

# TTL add 255 ==> add -1 ==> dec 1
tc_ct_setup() {
	CMD=$1
	GC_PORT=$2
	GS_IP=$3
	CLI_IP=$4
	CLI_PORT=$5

	LOADER_IP=5.5.5.5
	LOADER_DEV_MAC=98:03:9b:48:1f:fc
	RP_PRIV_LEG_DEV=enp6s0
	RP_PRIV_LEG_IP=5.5.5.2
	RP_PRIV_LEG_MAC=98:03:9b:c6:d4:cc
	RP_PUB_LEG_DEV=enp7s0
	RP_PUB_LEG_IP=30.30.30.100
	RP_PUB_LEG_MAC=98:03:9b:c6:d4:cd
	INITIATOR_IP=30.30.30.20
	INITIATOR_DEV_MAC=98:03:9b:c6:b1:94

	#RP_PRIV_LEG_DEV=eth0
	#RP_PRIV_LEG_IP=10.0.20.5
	#RP_PRIV_LEG_MAC=98:03:9b:c6:d2:d8
	#RP_PUB_LEG_DEV=eth1
	#RP_PUB_LEG_IP=24.51.15.230
	#RP_PUB_LEG_MAC=98:03:9b:c6:d2:ac
	#INITIATOR_DEV_MAC=00:1c:73:00:aa:80
	#LOADER_DEV_MAC=$INITIATOR_DEV_MAC

	if [ $CMD = "reset" ]
	then
		set +e
		tc qdisc del dev ${RP_PRIV_LEG_DEV} ingress
		tc qdisc del dev ${RP_PUB_LEG_DEV} ingress
		set -e
	elif [ $CMD = "initialize" ]
	then
		set +e
		tc qdisc del dev ${RP_PRIV_LEG_DEV} ingress
		tc qdisc del dev ${RP_PUB_LEG_DEV} ingress
		set -e
		tc qdisc add dev ${RP_PRIV_LEG_DEV} ingress
		tc qdisc add dev ${RP_PUB_LEG_DEV} ingress

		# 3.b DNAT and start tracking in z3 on the private side.
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action ct clear pipe action ct zone 3 nat pipe action goto chain 3

		# 2. If this is new in z5, this is the initiator, start tracking in z2
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 8 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+new action ct clear pipe action ct zone 2 goto chain 2

		# 2.a If this matches z5, this is a response, continue tracking in z4
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 8 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action ct clear pipe action ct zone 4 nat pipe action goto chain 9

		# 4.a For new connections SNAT an forward on the private side
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 3 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+new action ct commit zone 3 nat src addr ${RP_PRIV_LEG_IP} pipe action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${LOADER_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}

		# 3.1 For est connections, SNAT and forward on the private side
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 9 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${LOADER_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}

		# 4.b For est connections SNAT an forward on the private side
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 3 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${LOADER_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}

		# 11.a For est connection, this is a response, track in z2
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 4 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action ct clear pipe action ct zone 2 nat pipe action goto chain 5

		# 11.b For new connection, this is an initiator, track in z4
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 4 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+new action ct clear pipe action ct zone 4 nat action goto chain 6

		# 12.1 For est initiator, track in z5
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 6 proto ip flower ip_flags nofrag ip_proto udp dst_port $GC_PORT ct_state +trk+est ct clear pipe action ct zone 5 nat pipe action goto chain 7

		# 12.a For est response, SNAT and forward on the pub side
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 5 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PUB_LEG_MAC} munge eth dst set ${INITIATOR_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PUB_LEG_DEV}

		# 13.a For new initiator, SNAT and forward on the pub side
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 7 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+new action ct commit zone 5 nat src addr ${RP_PUB_LEG_IP} pipe action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PUB_LEG_MAC} munge eth dst set ${INITIATOR_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PUB_LEG_DEV}

		# 13.b For est initiator, SNAT and forward on the pub side
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 7 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PUB_LEG_MAC} munge eth dst set ${INITIATOR_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PUB_LEG_DEV}
	else
		# remove existing rules for the port
		set +e
		iptables -n -L -t nat --line-number | grep dpt:${GC_PORT} | awk '{print $1}' | xargs iptables -t nat -D PREROUTING
		conntrack -D -p udp --dport ${GC_PORT}
		set -e

		# 1. Pkt entering pub side; track in z5 to see if this is a response
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto udp dst_port $GC_PORT ct_state -trk action ct clear pipe action ct zone 5 nat pipe action goto chain 8

		# 10. Pkt enterig priv side; track in z3 to see if this is a response
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag src_ip ${GS_IP} ip_proto udp ct_state -trk action ct clear pipe action ct zone 3 nat pipe action goto chain 4

		# 12.1 For new initiator, dnat to cli address and track in z5
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 6 proto ip flower ip_flags nofrag ip_proto udp dst_port $GC_PORT ct_state +trk+new action ct commit zone 4 nat dst addr ${CLI_IP} port ${CLI_PORT} pipe action ct clear pipe action ct zone 5 pipe action goto chain 7

		# 3.a DNAT and start tracking in z3 on the private side.
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto udp dst_port $GC_PORT ct_state +trk+new action ct clear pipe action ct commit zone 2 nat dst addr ${GS_IP} port 47998 pipe action ct clear pipe action ct zone 3 pipe action goto chain 3

	fi

}

### main ###

if [ $1 = "initialize" -o $1 = "reset" ]
then
	tc_ct_setup $1 0 0
	exit 0
fi
CMD=$1
TC_OFFLOAD_PORT=${2:-8000}
GS_IP=$3
#IP_TABLE_PATH=/root/git/tools/1000ips
#index=$((TC_OFFLOAD_PORT-PUB_START_PORT))
#index=$((index+1))
#GS_IP=`cat $IP_TABLE_PATH | head -${index} | tail -1`
if [ -z $GS_IP ]
then
	GS_IP=`iptables -n -L -t nat  | grep ${TC_OFFLOAD_PORT} | tr -s " " | cut -d " " -f11| cut -d":" -f2`
fi
echo $1 $TC_OFFLOAD_PORT $GS_IP
tc_ct_setup $1 $TC_OFFLOAD_PORT $GS_IP
