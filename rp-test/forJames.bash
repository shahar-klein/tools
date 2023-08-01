# TTL add 255 ==> add -1 ==> dec 1
tc_ct_setup() {

	RP_PRIV_LEG_DEV=${1}
	RP_PRIV_LEG_MAC=${2}
	RP_PRIV_LEG_IP=${3}
	RP_PUB_LEG_DEV=${4}
	RP_PUB_LEG_MAC=${5}
	RP_PUB_LEG_IP=${6}
	PRIV_DEFGW_MAC=${7}
	PUB_DEFGW_MAC=${8}
	GFN_GS_IP=${9}
	GFN_CLIENT_PORT=${10}
	GFN_VIDEO_PORT=${11}

	set +e
	tc qdisc del dev ${RP_PRIV_LEG_DEV} ingress
	tc qdisc del dev ${RP_PUB_LEG_DEV} ingress
	set -e
	tc qdisc add dev ${RP_PRIV_LEG_DEV} ingress
	tc qdisc add dev ${RP_PUB_LEG_DEV} ingress

	# Chain 0, packet enters public side, clear ct state.
	tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto udp dst_port ${GFN_CLIENT_PORT} action ct clear pipe action goto chain 1

	# Chain 1, packet enters public side, start tracking in Zone 2
	tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 1 proto ip flower ip_flags nofrag ip_proto udp dst_port ${GFN_CLIENT_PORT} ct_state -trk action ct zone 2 nat pipe action goto chain 2

	# Chain 2, DNAT in Zone 2, start tracking in Zone 3 for SNAT 
	tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto udp dst_port ${GFN_CLIENT_PORT} ct_state +trk+new action ct commit zone 2 nat dst addr ${GFN_GS_IP} port ${GFN_VIDEO_PORT} pipe action ct clear pipe action ct zone 3 pipe action goto chain 3

	tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action ct clear pipe action ct zone 3 nat pipe action goto chain 3

	# Chain 3, SNAT in Zone 3 and forward
	tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 3 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+new action ct commit zone 3 nat src addr ${RP_PRIV_LEG_IP} pipe action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${PRIV_DEFGW_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}

	tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 3 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${PRIV_DEFGW_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}


	# Chain 0, packet enters private side, clear ct state.
	tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto udp src_port ${GFN_VIDEO_PORT} action ct clear pipe action goto chain 4

	# Chain 4, packet enters private side, start tracking in Zone 3 for SNAT
	tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 4 proto ip flower ip_flags nofrag ip_proto udp src_port ${GFN_VIDEO_PORT} ct_state -trk action ct zone 3 nat pipe action goto chain 5

	# Chain 5, established flows proceed to Zone 2 after SNAT for DNAT
	tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 5 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action ct clear pipe action ct zone 2 nat pipe action goto chain 6

	# Chain 6, established flows proceed to forwarding
	tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 6 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PUB_LEG_MAC} munge eth dst set ${PUB_DEFGW_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PUB_LEG_DEV}
}

tc_ct_setup $@
