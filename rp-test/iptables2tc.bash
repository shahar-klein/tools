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

# TTL add 255 ==> add -1 ==> dec 1
tc_ct_setup() {
	CMD=$1
	GC_PORT=$2
	GS_IP=$3
	LOADER_IP=5.5.5.5
	LOADER_DEV_MAC=98:03:9b:48:1f:fc
	RP_PRIV_LEG_DEV=enp6s0
	RP_PRIV_LEG_IP=5.5.5.2
	RP_PRIV_LEG_MAC=98:03:9b:c6:d4:cc
	INITIATOR_IP=30.30.30.20
	INITIATOR_DEV_MAC=98:03:9b:4f:b1:94
	RP_PUB_LEG_DEV=enp7s0
	RP_PUB_LEG_IP=30.30.30.100
	RP_PUB_LEG_MAC=98:03:9b:c6:d4:cd

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

		# Packets on the public leg
		# Chain 0, packet enters public side, start tracking in Zone 2
		#tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto udp ct_state -trk action ct zone 2 nat pipe action goto chain 2

		# 2.b Chain 2, DNAT in Zone 2, NAT established packets in Zone 3 for SNAT 
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action ct clear pipe action ct zone 3 nat pipe action goto chain 3

		# 3.a Chain 3, SNAT in Zone 3 and forward
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 3 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+new action ct commit zone 3 nat src addr ${RP_PRIV_LEG_IP} pipe action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${LOADER_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}

		# 3.b Chain 3, SNAT in Zone 3 and forward
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 3 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${LOADER_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}

		# Chain 0, packet enters private side, start tracking in Zone 3 for SNAT
		# tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto udp ct_state -trk action ct zone 3 nat pipe action goto chain 4

		# 4.a Chain 4, new flows are dropped
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 4 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+new action drop

		# 4.b Chain 4, established flows proceed to Zone 2 after SNAT for DNAT
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 4 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action ct clear pipe action ct zone 2 nat pipe action goto chain 5

		# 5 Chain 5, established flows proceed to forwarding
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 5 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PUB_LEG_MAC} munge eth dst set ${INITIATOR_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PUB_LEG_DEV}
	else
		# remove existing rules for the port
		set +e
		iptables -n -L -t nat --line-number | grep dpt:${GC_PORT} | awk '{print $1}' | xargs iptables -t nat -D PREROUTING
		conntrack -D -p udp --dport ${GC_PORT}
		set -e

		# 1. Packet entering the public side for the dst_port we are interested in. 
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto udp dst_port $GC_PORT ct_state -trk action ct clear pipe action ct zone 2 nat pipe action goto chain 2

		# 4. Packet entering the private side from the GS IP mapped to the port we are interested in.
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag src_ip ${GS_IP} ip_proto udp ct_state -trk action ct clear pipe action ct zone 3 nat pipe action goto chain 4

		# 2.a Chain 2, DNAT in Zone 2, start tracking in Zone 3 for SNAT 
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto udp dst_port $GC_PORT ct_state +trk+new action ct commit zone 2 nat dst addr ${GS_IP} port 47998 pipe action ct clear pipe action ct zone 3 pipe action goto chain 3

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
