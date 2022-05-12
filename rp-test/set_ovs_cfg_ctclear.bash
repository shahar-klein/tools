#!/bin/bash


set -u
set -e

ovs_forward_setup() {

	BRPRIV=$1
	BRPUB=$2
	RP_PRIV_LEG_DEV=$3
	RP_PUB_LEG_DEV=$4
	RP_PRIV_PATCH_PORT=$5
	RP_PUB_PATCH_PORT=$6
	RP_PRIV_LEG_MAC=$7
	RP_PUB_LEG_MAC=$8
	LOADER_IP=$9
	INITIATOR_IP=${10}
	LOADER_DEV_MAC=${11}
	INITIATOR_DEV_MAC=${12}

	# Add forwarding rules
	echo "priority=100,udp,nw_dst=$LOADER_IP,action=$RP_PUB_PATCH_PORT" >> /tmp/flows.${BRPUB}.$$
	echo "priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,nw_dst=$LOADER_IP,action=mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,normal"  >> /tmp/flows.${BRPRIV}.$$
	echo "priority=100,udp,nw_dst=$INITIATOR_IP,action=$RP_PRIV_PATCH_PORT" >> /tmp/flows.${BRPRIV}.$$
	echo "priority=100,in_port=$RP_PUB_PATCH_PORT,udp,nw_dst=$INITIATOR_IP,action=mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$INITIATOR_DEV_MAC,normal" >> /tmp/flows.${BRPUB}.$$
}

ovs_forward_nat_setup() {

	BRPRIV=$1
	BRPUB=$2
	RP_PRIV_LEG_DEV=$3
	RP_PUB_LEG_DEV=$4
	RP_PRIV_PATCH_PORT=$5
	RP_PUB_PATCH_PORT=$6
	RP_PRIV_LEG_MAC=$7
	RP_PUB_LEG_MAC=$8
	LOADER_IP=$9
	INITIATOR_IP=${10}
	NUM_SESSIONS=${11}
	GFN_PUB_PORT_START=${12}
	GS_PORT_START=${13}
	LOADER_DEV_MAC=${14}
	INITIATOR_DEV_MAC=${15}
	RP_PRIV_LEG_IP=${16}
	RP_PUB_LEG_IP=${17}

	# XXX In the multi-IP case we need a MAC for each IP.
	if [ $IS_MULTI = "no" ] ; then 
		for ((i = 0; i < $NUM_SESSIONS; i++)); do
			GC_PORT=$((GFN_PUB_PORT_START+i))
			GS_PORT=$((GS_PORT_START+i))

			# Add the pub side of the flows
			echo "priority=100,udp,nw_dst=$RP_PUB_LEG_IP,tp_dst=$GC_PORT,action=mod_nw_dst=$LOADER_IP,mod_tp_dst=$GS_PORT,$RP_PUB_PATCH_PORT" >> /tmp/flows.${BRPUB}.$$
			echo "priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,nw_dst=$LOADER_IP,tp_dst=$GS_PORT,action=mod_nw_src=$RP_PRIV_LEG_IP,mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,normal" >> /tmp/flows.${BRPRIV}.$$
                        
			# Add the priv _side of the flows
			echo "priority=100,udp,nw_dst=$RP_PRIV_LEG_IP,tp_src=$GS_PORT,action=mod_nw_dst=$INITIATOR_IP,mod_tp_dst=$GC_PORT,$RP_PRIV_PATCH_PORT" >> /tmp/flows.${BRPRIV}.$$
			echo "priority=100,in_port=$RP_PUB_PATCH_PORT,udp,nw_dst=$INITIATOR_IP,tp_dst=$GC_PORT,action=mod_nw_src=$RP_PUB_LEG_IP,mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$INITIATOR_DEV_MAC,normal" >> /tmp/flows.${BRPUB}.$$
		done
	else 
		GC_PORT=$GFN_PUB_PORT_START
		GS_PORT=$GS_PORT_START
		for GS_IP in `cat /root/git/tools/1000ips` ; do

			# Add the pub side of the flows
			echo "priority=100,udp,nw_dst=$RP_PUB_LEG_IP,tp_dst=$GC_PORT,action=mod_nw_dst=$GS_IP,mod_tp_dst=47998,$RP_PUB_PATCH_PORT" >> /tmp/flows.${BRPUB}.$$
			echo "priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,nw_dst=$GS_IP,tp_dst=47998,action=dec_ttl,mod_nw_src=$RP_PRIV_LEG_IP,mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,normal" >> /tmp/flows.${BRPRIV}.$$
                        
			# Add the priv _side of the flows
			echo "priority=100,udp,nw_src=$GS_IP,tp_src=47998,action=mod_nw_dst=$INITIATOR_IP,mod_tp_src=$GC_PORT,$RP_PRIV_PATCH_PORT" >> /tmp/flows.${BRPRIV}.$$
			echo "priority=100,in_port=$RP_PUB_PATCH_PORT,udp,nw_dst=$INITIATOR_IP,tp_src=$GC_PORT,action=dec_ttl,mod_nw_src=$RP_PUB_LEG_IP,mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$INITIATOR_DEV_MAC,normal" >> /tmp/flows.${BRPUB}.$$

			GC_PORT=$((GC_PORT+1))
			GS_PORT=$((GS_PORT+1))
		done
	fi
}

# TTL add 255 ==> add -1 ==> dec 1
tc_ct_pp_setup() {

	BRPRIV=$1
	BRPUB=$2
	RP_PRIV_LEG_DEV=$3
	RP_PUB_LEG_DEV=$4
	RP_PRIV_PATCH_PORT=$5
	RP_PUB_PATCH_PORT=$6
	RP_PRIV_LEG_MAC=$7
	RP_PUB_LEG_MAC=$8
	LOADER_IP=$9
	INITIATOR_IP=${10}
	NUM_SESSIONS=${11}
	GFN_PUB_PORT_START=${12}
	GS_PORT_START=${13}
	LOADER_DEV_MAC=${14}
	INITIATOR_DEV_MAC=${15}
	RP_PRIV_LEG_IP=${16}
	RP_PUB_LEG_IP=${17}


	set +e
	tc qdisc del dev ${RP_PRIV_LEG_DEV} ingress
	tc qdisc del dev ${RP_PUB_LEG_DEV} ingress
	set -e
	tc qdisc add dev ${RP_PRIV_LEG_DEV} ingress
	tc qdisc add dev ${RP_PUB_LEG_DEV} ingress
	if [ $IS_MULTI = "no" ] ; then 
		# Chain 0, packet enters public side, start tracking in Zone 2
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto udp ct_state -trk action ct zone 2 nat pipe action goto chain 2
		for ((i = 0; i < $NUM_SESSIONS; i++)); do
			GC_PORT=$((GFN_PUB_PORT_START+i))
			GS_PORT=$((GS_PORT_START+i))

			# Chain 2, DNAT in Zone 2, start tracking in Zone 3 for SNAT 
			tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto udp dst_port $GC_PORT ct_state +trk+new action ct commit zone 2 nat dst addr ${LOADER_IP} port $GS_PORT pipe action ct clear pipe action ct zone 3 pipe action goto chain 3

		done

		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est  action ct clear pipe action ct zone 3 nat pipe action goto chain 3

		# Chain 3, SNAT in Zone 3 and forward
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 3 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+new action ct commit zone 3 nat src addr ${RP_PRIV_LEG_IP} pipe action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${LOADER_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}

		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 3 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${LOADER_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}


		# Chain 0, packet enters private side, start tracking in Zone 3 for SNAT
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto udp ct_state -trk action ct zone 3 nat pipe action goto chain 4

		# Chain 4, established flows proceed to Zone 2 after SNAT for DNAT
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 4 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action ct clear pipe action ct zone 2 nat pipe action goto chain 5

		# Chain 5, established flows proceed to forwarding
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 5 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe pedit ex munge eth src set ${RP_PUB_LEG_MAC} munge eth dst set ${INITIATOR_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PUB_LEG_DEV}


	else
		GC_PORT=$GFN_PUB_PORT_START
		GS_PORT=$GS_PORT_START
		PRIORITY=0
		# Chain 0, packet enters public side, start tracking in Zone 2
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto udp ct_state -trk action ct zone 2 nat pipe action goto chain 2

		for GS_IP in `cat /root/git/tools/1000ips` ; do

			# Chain 2, DNAT in Zone 2, start tracking in Zone 3 for SNAT 
			tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto udp dst_port $GC_PORT ct_state +trk+new action ct commit zone 2 nat dst addr ${GS_IP} port 47998 pipe action ct clear pipe action ct zone 3 pipe action goto chain 3

			# Chain 0, packet enters private side, assign priority, and start tracking in Zone 3 for SNAT
			#tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 0 proto ip flower src_ip ${GS_IP} ip_flags nofrag ip_proto udp ct_state -trk action skbedit priority $PRIORITY pipe action ct zone 3 nat pipe action goto chain 4
			# Chain 5, established flows proceed to forwarding
			# tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 5 proto ip flower src_ip ${GS_IP} ip_flags nofrag ip_proto udp  action skbedit priority $PRIORITY action goto chain 6

			PRIHEX=`printf '%x' $PRIORITY`
		 	tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 5 proto ip flower ip_flags nofrag ip_proto udp src_port $GC_PORT ct_state +trk+est action skbedit priority $PRIHEX pipe action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PUB_LEG_MAC} munge eth dst set ${INITIATOR_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PUB_LEG_DEV}

			GC_PORT=$((GC_PORT+1))
			GS_PORT=$((GS_PORT+1))
			PRIORITY=$((PRIORITY+1))
		done

		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action ct clear pipe action ct zone 3 nat pipe action goto chain 3

		# Chain 3, SNAT in Zone 3 and forward
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 3 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+new action ct commit zone 3 nat src addr ${RP_PRIV_LEG_IP} pipe action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${LOADER_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 3 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${LOADER_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}

		# Chain 0, packet enters private side, assign priority, and start tracking in Zone 3 for SNAT
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto udp ct_state -trk action ct zone 3 nat pipe action goto chain 4

		# Chain 4, established flows proceed to Zone 2 after SNAT for DNAT
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 4 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action ct clear pipe action ct zone 2 nat pipe action goto chain 5

		# Chain 5, established flows proceed to forwarding
		# tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 5 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PUB_LEG_MAC} munge eth dst set ${INITIATOR_DEV_MAC} pipe action csum iph and udp pipe action skbedit priority 0x5 pipe action mirred egress redirect dev ${RP_PUB_LEG_DEV}

	fi
}


# TTL add 255 ==> add -1 ==> dec 1
tc_ct_setup() {

	BRPRIV=$1
	BRPUB=$2
	RP_PRIV_LEG_DEV=$3
	RP_PUB_LEG_DEV=$4
	RP_PRIV_PATCH_PORT=$5
	RP_PUB_PATCH_PORT=$6
	RP_PRIV_LEG_MAC=$7
	RP_PUB_LEG_MAC=$8
	LOADER_IP=$9
	INITIATOR_IP=${10}
	NUM_SESSIONS=${11}
	GFN_PUB_PORT_START=${12}
	GS_PORT_START=${13}
	LOADER_DEV_MAC=${14}
	INITIATOR_DEV_MAC=${15}
	RP_PRIV_LEG_IP=${16}
	RP_PUB_LEG_IP=${17}


	set +e
	tc qdisc del dev ${RP_PRIV_LEG_DEV} ingress
	tc qdisc del dev ${RP_PUB_LEG_DEV} ingress
	set -e
	tc qdisc add dev ${RP_PRIV_LEG_DEV} ingress
	tc qdisc add dev ${RP_PUB_LEG_DEV} ingress
	if [ $IS_MULTI = "no" ] ; then 
		# Chain 0, packet enters public side, start tracking in Zone 2
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto udp ct_state -trk action ct zone 2 nat pipe action goto chain 2
		for ((i = 0; i < $NUM_SESSIONS; i++)); do
			GC_PORT=$((GFN_PUB_PORT_START+i))
			GS_PORT=$((GS_PORT_START+i))

			# Chain 2, DNAT in Zone 2, start tracking in Zone 3 for SNAT 
			tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto udp dst_port $GC_PORT ct_state +trk+new action ct commit zone 2 nat dst addr ${LOADER_IP} port $GS_PORT pipe action ct clear pipe action ct zone 3 pipe action goto chain 3

		done

		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est  action ct clear pipe action ct zone 3 nat pipe action goto chain 3

		# Chain 3, SNAT in Zone 3 and forward
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 3 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+new action ct commit zone 3 nat src addr ${RP_PRIV_LEG_IP} pipe action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${LOADER_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}

		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 3 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${LOADER_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}


		# Chain 0, packet enters private side, start tracking in Zone 3 for SNAT
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto udp ct_state -trk action ct zone 3 nat pipe action goto chain 4

		# Chain 4, established flows proceed to Zone 2 after SNAT for DNAT
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 4 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action ct clear pipe action ct zone 2 nat pipe action goto chain 5

		# Chain 5, established flows proceed to forwarding
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 5 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe pedit ex munge eth src set ${RP_PUB_LEG_MAC} munge eth dst set ${INITIATOR_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PUB_LEG_DEV}


	else
		GC_PORT=$GFN_PUB_PORT_START
		GS_PORT=$GS_PORT_START
		PRIORITY=0

		# Chain 0, packet enters public side, start tracking in Zone 2
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto udp ct_state -trk action ct zone 2 nat pipe action goto chain 2

		for GS_IP in `cat /root/git/tools/1000ips` ; do

			# Chain 2, DNAT in Zone 2, start tracking in Zone 3 for SNAT 
			tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto udp dst_port $GC_PORT ct_state +trk+new action ct commit zone 2 nat dst addr ${GS_IP} port 47998 pipe action ct clear pipe action ct zone 3 pipe action goto chain 3
			GC_PORT=$((GC_PORT+1))
			GS_PORT=$((GS_PORT+1))
		done

		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 2 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action ct clear pipe action ct zone 3 nat pipe action goto chain 3

		# Chain 3, SNAT in Zone 3 and forward
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 3 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+new action ct commit zone 3 nat src addr ${RP_PRIV_LEG_IP} pipe action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${LOADER_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}
		tc filter add dev ${RP_PUB_LEG_DEV} ingress prio 1 chain 3 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PRIV_LEG_MAC} munge eth dst set ${LOADER_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PRIV_LEG_DEV}


		# Chain 0, packet enters private side, start tracking in Zone 3 for SNAT
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 0 proto ip flower ip_flags nofrag ip_proto udp ct_state -trk action ct zone 3 nat pipe action goto chain 4

		# Chain 4, established flows proceed to Zone 2 after SNAT for DNAT
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 4 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action ct clear pipe action ct zone 2 nat pipe action goto chain 5

		PRIHEX=`printf '%x' $PRIORITY`
		# Chain 5, established flows proceed to forwarding
		tc filter add dev ${RP_PRIV_LEG_DEV} ingress prio 1 chain 5 proto ip flower ip_flags nofrag ip_proto udp ct_state +trk+est action skbedit priority $PRIHEX pipe action pedit ex munge ip ttl add 255 pipe action pedit ex munge eth src set ${RP_PUB_LEG_MAC} munge eth dst set ${INITIATOR_DEV_MAC} pipe action csum iph and udp pipe action mirred egress redirect dev ${RP_PUB_LEG_DEV}

	fi
}

ovs_forward_ct_setup() {

	BRPRIV=$1
	BRPUB=$2
	RP_PRIV_LEG_DEV=$3
	RP_PUB_LEG_DEV=$4
	RP_PRIV_PATCH_PORT=$5
	RP_PUB_PATCH_PORT=$6
	RP_PRIV_LEG_MAC=$7
	RP_PUB_LEG_MAC=$8
	LOADER_IP=$9
	INITIATOR_IP=${10}
	NUM_SESSIONS=${11}
	GFN_PUB_PORT_START=${12}
	GS_PORT_START=${13}
	LOADER_DEV_MAC=${14}
	INITIATOR_DEV_MAC=${15}
	RP_PRIV_LEG_IP=${16}
	RP_PUB_LEG_IP=${17}

		if [ $IS_MULTI = "no" ] ; then 
			for ((i = 0; i < $NUM_SESSIONS; i++)); do
				GC_PORT=$((GFN_PUB_PORT_START+i))
				GS_PORT=$((GS_PORT_START+i))

				# Add the pub side of the flows
				echo "priority=100,in_port=$RP_PUB_LEG_DEV,udp,action=ct(zone=10,nat,table=11)" >> /tmp/flows.${BRPUB}.$$
				echo "table=11,priority=100,udp,tp_dst=$GC_PORT,ct_state=+trk+new,action=ct(commit,zone=10,nat(dst=$LOADER_IP:$GS_PORT)),$RP_PUB_PATCH_PORT" >> /tmp/flows.${BRPUB}.$$
				echo "table=11,priority=100,ct_state=+trk+est,action=$RP_PUB_PATCH_PORT" >> /tmp/flows.${BRPUB}.$$
				echo "priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,action=ct_clear,ct(zone=12,nat,table=13)" >> /tmp/flows.${BRPRIV}.$$
	                        
				# XXX We don't need "udp,tp_dst=$GS_PORT" since all of these ports are in the same host, hence same LOADER_DEV_MAC, if that changes
				# this'll be needed - keeping it for now.
				echo "table=13,udp,tp_dst=$GS_PORT,ct_state=+trk+new,action=ct(commit,zone=12,nat(src=$RP_PRIV_LEG_IP)),mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,normal" >> /tmp/flows.${BRPRIV}.$$
	                        
				echo "table=13,ct_state=+trk+est,action=mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,normal" >> /tmp/flows.${BRPRIV}.$$
	                        
				# Add the priv _side of the flows
				echo "priority=100,in_port=$RP_PRIV_LEG_DEV,udp,action=ct(zone=12,nat,table=14)" >> /tmp/flows.${BRPRIV}.$$
				echo "table=14,priority=100,udp,ct_state=+trk+est,action=$RP_PRIV_PATCH_PORT" >> /tmp/flows.${BRPRIV}.$$
				echo "priority=100,in_port=$RP_PUB_PATCH_PORT,udp,action=ct_clear,ct(zone=10,nat,table=15)" >> /tmp/flows.${BRPUB}.$$
				echo "table=15,priority=100,ct_state=+trk+est,action=mod_nw_src=$RP_PUB_LEG_IP,mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$INITIATOR_DEV_MAC,normal" >> /tmp/flows.${BRPUB}.$$
			done
		else
			GC_PORT=$GFN_PUB_PORT_START
			GS_PORT=$GS_PORT_START
			for GS_IP in `cat /root/git/tools/1000ips` ; do
				echo "priority=100,in_port=$RP_PUB_LEG_DEV,udp,action=ct(zone=10,nat,table=11)" >> /tmp/flows.${BRPUB}.$$
				echo "table=11,priority=100,udp,tp_dst=$GC_PORT,ct_state=+trk+new,action=ct(commit,zone=10,nat(dst=$GS_IP:47998)),$RP_PUB_PATCH_PORT" >> /tmp/flows.${BRPUB}.$$
				echo "table=11,priority=100,ct_state=+trk+est,action=$RP_PUB_PATCH_PORT" >> /tmp/flows.${BRPUB}.$$
				echo "priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,action=ct_clear,ct(zone=12,nat,table=13)" >> /tmp/flows.${BRPRIV}.$$
	                        
				# XXX We don't need "udp,nw_dst=$GS_IP" since all of these IPs are in the same host, hence same LOADER_DEV_MAC, if that changes
				# this'll be needed - keeping it for now.
				echo "table=13,udp,nw_dst=$GS_IP,tp_dst=47998,ct_state=+trk+new,action=ct(commit,zone=12,nat(src=$RP_PRIV_LEG_IP)),mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,normal" >> /tmp/flows.${BRPRIV}.$$
	                        
				echo "table=13,ct_state=+trk+est,action=mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,dec_ttl,normal" >> /tmp/flows.${BRPRIV}.$$
	                        
	                        
				# Add the priv _side of the flows
				echo "priority=100,in_port=$RP_PRIV_LEG_DEV,udp,action=ct(zone=12,nat,table=14)" >> /tmp/flows.${BRPRIV}.$$
				echo "table=14,priority=100,ct_state=+trk+est,action=$RP_PRIV_PATCH_PORT" >> /tmp/flows.${BRPRIV}.$$
				echo "priority=100,in_port=$RP_PUB_PATCH_PORT,udp,action=ct_clear,ct(zone=10,nat,table=15)" >> /tmp/flows.${BRPUB}.$$
				echo "table=15,priority=100,ct_state=+trk+est,action=mod_nw_src=$RP_PUB_LEG_IP,mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$INITIATOR_DEV_MAC,dec_ttl,normal" >> /tmp/flows.${BRPUB}.$$

				GC_PORT=$((GC_PORT+1))
				GS_PORT=$((GS_PORT+1))
			done
		fi
}


### main ###


mode=$1
IS_MULTI=${2:-no}
BRPRIV=$3
BRPUB=$4
RP_PRIV_LEG_DEV=$5
RP_PUB_LEG_DEV=$6
RP_PRIV_PATCH_PORT=$7
RP_PUB_PATCH_PORT=$8
shift
shift

if [ $mode != "tc_ct_setup" ] ; then 
	if [ -f /tmp/flows.${BRPRIV}.$$ ]; then
		rm -f /tmp/flows.${BRPRIV}.$$
	fi
	
	if [ -f /tmp/flows.${BRPUB}.$$ ]; then
		rm -f /tmp/flows.${BRPUB}.$$
	fi
	
	#Add ARP rules
	echo "priority=10,arp,action=normal" >> /tmp/flows.${BRPRIV}.$$
	echo "priority=50,in_port=$RP_PRIV_PATCH_PORT,arp,action=drop" >> /tmp/flows.${BRPRIV}.$$
	echo "priority=50,in_port=$RP_PRIV_PATCH_PORT,ip6,action=drop" >> /tmp/flows.${BRPRIV}.$$
	echo "priority=50,in_port=$RP_PRIV_PATCH_PORT,dl_dst=ff:ff:ff:ff:ff:ff,action=drop" >> /tmp/flows.${BRPRIV}.$$
	       
	       
	# Add ARP to the pub bridge
	echo "priority=10,arp,action=normal" >> /tmp/flows.${BRPUB}.$$
	echo "priority=50,in_port=$RP_PUB_PATCH_PORT,arp,action=drop" >> /tmp/flows.${BRPUB}.$$
	echo "priority=50,in_port=$RP_PUB_PATCH_PORT,ip6,action=drop" >> /tmp/flows.${BRPUB}.$$
	echo "priority=50,in_port=$RP_PUB_PATCH_PORT,dl_dst=ff:ff:ff:ff:ff:ff,action=drop" >> /tmp/flows.${BRPUB}.$$
fi
case  $mode in
	ovs_forward_setup)
		ovs_forward_setup $@
		;;
	ovs_forward_nat_setup)
		ovs_forward_nat_setup $@
		;;
	ovs_forward_ct_setup)
		ovs_forward_ct_setup $@
		;;
	tc_ct_setup)
		tc_ct_setup $@
		;;
	tc_ct_pp_setup)
		tc_ct_pp_setup $@
		;;
esac

if [ $mode != "tc_ct_setup" -a $mode != "tc_ct_pp_setup" ] ; then 
	# XXX Check if we can add these to the file as well.
	ovs-ofctl del-flows ${BRPRIV}
	ovs-ofctl del-flows ${BRPUB}
	
	ovs-ofctl add-flows ${BRPRIV} /tmp/flows.${BRPRIV}.$$
	ovs-ofctl add-flows ${BRPUB} /tmp/flows.${BRPUB}.$$
fi
