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

	# Add forwarding rules
	ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_LEG_DEV,udp,nw_dst=$LOADER_IP,action=$RP_PUB_PATCH_PORT
	ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,nw_dst=$LOADER_IP,action=mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,$RP_PRIV_LEG_DEV
	ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_LEG_DEV,udp,nw_dst=$INITIATOR_IP,action=$RP_PRIV_PATCH_PORT
	ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_PATCH_PORT,udp,nw_dst=$INITIATOR_IP,action=mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$INITIATOR_DEV_MAC,$RP_PUB_LEG_DEV
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


	# XXX It'll take a long time to add these flows via ssh!
	for ((i = 0; i < $NUM_SESSIONS; i++)); do
		GC_PORT=$((GFN_PUB_PORT_START+i))
		GS_PORT=$((GS_PORT_START+i))

		# Add the pub side of the flows
		ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_LEG_DEV,udp,nw_dst=$RP_PUB_LEG_IP,tp_dst=$GC_PORT,action=mod_nw_dst=$LOADER_IP,mod_tp_dst=$GS_PORT,$RP_PUB_PATCH_PORT
		ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,nw_dst=$LOADER_IP,tp_dst=$GS_PORT,action=mod_nw_src=$RP_PRIV_LEG_IP,mod_tp_src=$RP_PORT,mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,$RP_PRIV_LEG_DEV

		# Add the priv _side of the flows
		ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_LEG_DEV,udp,nw_dst=$RP_PRIV_LEG_IP,tp_src=$GS_PORT,action=mod_nw_dst=$INITIATOR_IP,mod_tp_dst=$GC_PORT,$RP_PRIV_PATCH_PORT
		ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_PATCH_PORT,udp,nw_dst=$INITIATOR_IP,tp_dst=$GC_PORT,action=mod_nw_src=$RP_PUB_LEG_IP,mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$INITIATOR_DEV_MAC,$RP_PUB_LEG_DEV
	done

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

	# XXX It'll take a long time to add these flows via ssh!
	for ((i = 0; i < $NUM_SESSIONS; i++)); do
		GC_PORT=$((GFN_PUB_PORT_START+i))
		GS_PORT=$((GS_PORT_START+i))

		# Add the pub side of the flows
		ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_LEG_DEV,udp,action=ct\(zone=10,nat,table=11\)
		ovs-ofctl add-flow $BRPUB table=11,priority=100,in_port=$RP_PUB_LEG_DEV,udp,tp_dst=$GC_PORT,ct_state=+trk+new,action=ct\(commit,zone=10,nat\(dst=$LOADER_IP:$GS_PORT\)\),$RP_PUB_PATCH_PORT
		ovs-ofctl add-flow $BRPUB table=11,priority=100,in_port=$RP_PUB_LEG_DEV,udp,tp_dst=$GC_PORT,ct_state=+trk+est,action=ct\(zone=10,nat\),$RP_PUB_PATCH_PORT
		ovs-ofctl add-flow $BRPRIV in_port=$RP_PRIV_PATCH_PORT,udp,action=ct_clear,ct\(zone=12,nat,table=13\)

		ovs-ofctl add-flow $BRPRIV table=13,in_port=$RP_PRIV_PATCH_PORT,udp,tp_dst=$GS_PORT,ct_state=+trk+new,action=ct\(commit,zone=12,nat\(src=$RP_PRIV_LEG_IP\)\),mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,$RP_PRIV_LEG_DEV

		ovs-ofctl add-flow $BRPRIV table=13,in_port=$RP_PRIV_PATCH_PORT,udp,tp_dst=$GS_PORT,ct_state=+trk+est,action=ct\(zone=12,nat\),mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,$RP_PRIV_LEG_DEV


		# Add the priv _side of the flows
		ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_LEG_DEV,udp,action=ct\(zone=12,nat,table=14\)
		ovs-ofctl add-flow $BRPRIV table=14,priority=100,in_port=$RP_PRIV_LEG_DEV,udp,ct_state=+trk+est,action=$RP_PRIV_PATCH_PORT
		ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_PATCH_PORT,udp,action=ct_clear,ct\(zone=10,nat,table=15\)
		ovs-ofctl add-flow $BRPUB table=15,priority=100,in_port=$RP_PUB_PATCH_PORT,udp,ct_state=+trk+est,action=mod_nw_src=$RP_PUB_LEG_IP,mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$INITIATOR_DEV_MAC,$RP_PUB_LEG_DEV
	done

}


### main ###

mode=$1
shift
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
esac


