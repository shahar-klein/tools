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
	echo "priority=100,in_port=$RP_PUB_LEG_DEV,udp,nw_dst=$LOADER_IP,action=$RP_PUB_PATCH_PORT" >> /tmp/flows.${BRPUB}.$$
	echo "priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,nw_dst=$LOADER_IP,action=mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,$RP_PRIV_LEG_DEV"  >> /tmp/flows.${BRPRIV}.$$
	echo "priority=100,in_port=$RP_PRIV_LEG_DEV,udp,nw_dst=$INITIATOR_IP,action=$RP_PRIV_PATCH_PORT" >> /tmp/flows.${BRPRIV}.$$
	echo "priority=100,in_port=$RP_PUB_PATCH_PORT,udp,nw_dst=$INITIATOR_IP,action=mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$INITIATOR_DEV_MAC,$RP_PUB_LEG_DEV" >> /tmp/flows.${BRPUB}.$$
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


	for ((i = 0; i < $NUM_SESSIONS; i++)); do
		GC_PORT=$((GFN_PUB_PORT_START+i))
		GS_PORT=$((GS_PORT_START+i))

		# Add the pub side of the flows
		echo "priority=100,in_port=$RP_PUB_LEG_DEV,udp,nw_dst=$RP_PUB_LEG_IP,tp_dst=$GC_PORT,action=mod_nw_dst=$LOADER_IP,mod_tp_dst=$GS_PORT,$RP_PUB_PATCH_PORT" >> /tmp/flows.${BRPUB}.$$
		echo "priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,nw_dst=$LOADER_IP,tp_dst=$GS_PORT,action=mod_nw_src=$RP_PRIV_LEG_IP,mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,$RP_PRIV_LEG_DEV" >> /tmp/flows.${BRPRIV}.$$

		# Add the priv _side of the flows
		echo "priority=100,in_port=$RP_PRIV_LEG_DEV,udp,nw_dst=$RP_PRIV_LEG_IP,tp_src=$GS_PORT,action=mod_nw_dst=$INITIATOR_IP,mod_tp_dst=$GC_PORT,$RP_PRIV_PATCH_PORT" >> /tmp/flows.${BRPRIV}.$$
		echo "priority=100,in_port=$RP_PUB_PATCH_PORT,udp,nw_dst=$INITIATOR_IP,tp_dst=$GC_PORT,action=mod_nw_src=$RP_PUB_LEG_IP,mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$INITIATOR_DEV_MAC,$RP_PUB_LEG_DEV" >> /tmp/flows.${BRPUB}.$$
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
	LOADER_DEV_MAC=${14}
	INITIATOR_DEV_MAC=${15}
	RP_PRIV_LEG_IP=${16}
	RP_PUB_LEG_IP=${17}

	for ((i = 0; i < $NUM_SESSIONS; i++)); do
		GC_PORT=$((GFN_PUB_PORT_START+i))
		GS_PORT=$((GS_PORT_START+i))

		# Add the pub side of the flows
		echo "priority=100,in_port=$RP_PUB_LEG_DEV,udp,action=ct(zone=10,nat,table=11)" >> /tmp/flows.${BRPUB}.$$
		echo "table=11,priority=100,in_port=$RP_PUB_LEG_DEV,udp,tp_dst=$GC_PORT,ct_state=+trk+new,action=ct(commit,zone=10,nat(dst=$LOADER_IP:$GS_PORT)),$RP_PUB_PATCH_PORT" >> /tmp/flows.${BRPUB}.$$
		echo "table=11,priority=100,in_port=$RP_PUB_LEG_DEV,udp,tp_dst=$GC_PORT,ct_state=+trk+est,action=ct(zone=10,nat),$RP_PUB_PATCH_PORT" >> /tmp/flows.${BRPUB}.$$
		echo "in_port=$RP_PRIV_PATCH_PORT,udp,action=ct_clear,ct(zone=12,nat,table=13)" >> /tmp/flows.${BRPRIV}.$$

		echo "table=13,in_port=$RP_PRIV_PATCH_PORT,udp,tp_dst=$GS_PORT,ct_state=+trk+new,action=ct(commit,zone=12,nat(src=$RP_PRIV_LEG_IP)),mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,$RP_PRIV_LEG_DEV" >> /tmp/flows.${BRPRIV}.$$

		echo "table=13,in_port=$RP_PRIV_PATCH_PORT,udp,tp_dst=$GS_PORT,ct_state=+trk+est,action=ct(zone=12,nat),mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,$RP_PRIV_LEG_DEV" >> /tmp/flows.${BRPRIV}.$$


		# Add the priv _side of the flows
		echo "priority=100,in_port=$RP_PRIV_LEG_DEV,udp,action=ct(zone=12,nat,table=14)" >> /tmp/flows.${BRPRIV}.$$
		echo "table=14,priority=100,in_port=$RP_PRIV_LEG_DEV,udp,ct_state=+trk+est,action=$RP_PRIV_PATCH_PORT" >> /tmp/flows.${BRPRIV}.$$
		echo "priority=100,in_port=$RP_PUB_PATCH_PORT,udp,action=ct_clear,ct(zone=10,nat,table=15)" >> /tmp/flows.${BRPUB}.$$
		echo "table=15,priority=100,in_port=$RP_PUB_PATCH_PORT,udp,ct_state=+trk+est,action=mod_nw_src=$RP_PUB_LEG_IP,mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$INITIATOR_DEV_MAC,$RP_PUB_LEG_DEV" >> /tmp/flows.${BRPUB}.$$
	done

}


### main ###

mode=$1
BRPRIV=$2
BRPUB=$3
RP_PRIV_LEG_DEV=$4
RP_PUB_LEG_DEV=$5
RP_PRIV_PATCH_PORT=$6
RP_PUB_PATCH_PORT=$7


if [ -f /tmp/flows.${BRPUB}.$$ ]; then
	rm -f /tmp/flows.${BRPUB}.$$
fi
if [ -f /tmp/flows.${BRPRIV}.$$ ]; then
	rm -f /tmp/flows.${BRPRIV}.$$
fi
echo "del-flows" >> /tmp/flows.${BRPRIV}.$$
echo "del-flows" >> /tmp/flows.{BRPUB}.$$

#Add ARP rules
echo "priority=10,in_port=$RP_PRIV_LEG_DEV,arp,action=normal" > /tmp/flows.${BRPRIV}.$$
echo "priority=10,in_port=$BRPRIV,arp,action=normal" > /tmp/flows.${BRPRIV}.$$
echo "priority=50,in_port=$RP_PRIV_PATCH_PORT,arp,action=drop" > /tmp/flows.${BRPRIV}.$$
echo "priority=50,in_port=$RP_PRIV_PATCH_PORT,ip6,action=drop" > /tmp/flows.${BRPRIV}.$$
echo "priority=50,in_port=$RP_PRIV_PATCH_PORT,dl_dst=ff:ff:ff:ff:ff:ff,action=drop" > /tmp/flows.${BRPRIV}.$$
       
       
# Add ARP to the pub bridge
echo "priority=10,in_port=$RP_PUB_LEG_DEV,arp,action=normal" >> /tmp/flows.${BRPUB}.$$
echo "priority=10,in_port=$BRPUB,arp,action=normal" >> /tmp/flows.${BRPUB}.$$
echo "priority=50,in_port=$RP_PUB_PATCH_PORT,arp,action=drop" >> /tmp/flows.${BRPUB}.$$
echo "priority=50,in_port=$RP_PUB_PATCH_PORT,ip6,action=drop" >> /tmp/flows.${BRPUB}.$$
echo "priority=50,in_port=$RP_PUB_PATCH_PORT,dl_dst=ff:ff:ff:ff:ff:ff,action=drop" >> /tmp/flows.${BRPUB}.$$

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
ovs-ofctl add-flows ${BRPRIV} /tmp/flows.${BRPRIV}.$$
ovs-ofctl add-flows ${BRPUB} /tmp/flows.${BRPUB}.$$
