#!/bin/bash

GS_PRIV_ADDR=7.7.7.9
GS_PRIV_MAC=50:6b:4b:fb:ee:ea

RP_PRIV_LEG_ADDR=7.7.7.5
RP_PRIV_LEG_MAC=ec:0d:9a:d8:ff:16
RP_PRIV_LEG_DEV=ens5

RP_PUB_LEG_ADDR=9.9.9.6
RP_PUB_LEG_MAC=ec:0d:9a:d8:ff:17
RP_PUB_LEG_DEV=ens6

GC_PUB_ADDR=9.9.9.10
GC_PUB_MAC=98:03:9b:16:47:16

RP_PRIV_PATCH_PORT=priv-patch
RP_PUB_PATCH_PORT=pub-patch
BRPUB=brpub
BRPRIV=brpriv

GC_PORT_START=7000
RP_PORT_START=22000
GS_PORT_START=17000
NUM_SESSIONS=1000

# FORWARDING, FORWARDING_RP
MODE=FORWARDING_RP


#packet: 
#from GC: GC_PUB_ADDR:GC_PORT->RP_PUB_LEG_ADDR:RP_PUB_PORT
#DNAT to: GC_PUB_ADDR:GC_PORT->GS_PRIV_ADDR:GS_PORT
#SNAT to: RP_PRIV_LEG_ADDR:RP_PRIV_PORT->GS_PRIV_ADDR:GS_PORT

#from GS: GS_PRIV_ADDR:GS_PORT->RP_PRIV_LEG_ADDR:RP_PRIV_PORT
#DNAT to: GS_PRIV_ADDR:GS_PORT->GC_PUB_ADDR:GC_PORT
#SNAT to: RP_PUB_LEG_ADDR:RP_PUB_PORT->GC_PUB_ADDR:GC_PORT



#RP_PRIV_LEG_ADDR                        RP_PUB_LEG_ADDR
# +------------+                          +------------+
# |            |            PUB_PATCH_PORT|            |
# | BRPRIV     +--------------------------+ BRPUB      |
# |            |PRIV_PATCH_PORT           |            |
# |            |                          |            |
# |            |                          |            |
# +-----+------+                          +-----+------+
#       |                                       |
#       |                                       |
#       |                                       |
#       |                                       |
#       +                                       +
#RP_PRIV_LEG_DEV                         RP_PUB_LEG_DEV




#vs-vsctl set open . other-config:hw-offload=false

#cleanup
ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br

systemctl restart openvswitch-switch

ip l set dev $RP_PRIV_LEG_DEV up
ip l set dev $RP_PUB_LEG_DEV up
ip addr flush dev $RP_PRIV_LEG_DEV
ip addr flush dev $RP_PRIV_LEG_DEV

ovs-vsctl add-br $BRPRIV
ovs-ofctl del-flows $BRPRIV
ovs-vsctl add-port $BRPRIV $RP_PRIV_LEG_DEV

ovs-vsctl add-br $BRPUB
ovs-ofctl del-flows $BRPUB
ovs-vsctl add-port $BRPUB $RP_PUB_LEG_DEV

ip a add dev $BRPUB $RP_PUB_LEG_ADDR/24 
ip l set dev $BRPUB up

ip a add dev $BRPRIV $RP_PRIV_LEG_ADDR/24 
ip l set dev $BRPRIV up

ovs-vsctl set bridge $BRPRIV other-config:hwaddr=\"$RP_PRIV_LEG_MAC\"
ovs-vsctl set bridge $BRPUB other-config:hwaddr=\"$RP_PUB_LEG_MAC\"

# Create patch  ports

ovs-vsctl add-port $BRPRIV $RP_PRIV_PATCH_PORT -- set interface $RP_PRIV_PATCH_PORT type=patch options:peer=$RP_PUB_PATCH_PORT
ovs-vsctl add-port $BRPUB $RP_PUB_PATCH_PORT -- set interface $RP_PUB_PATCH_PORT type=patch options:peer=$RP_PRIV_PATCH_PORT

ovs-vsctl show

ovs-ofctl dump-ports-desc $BRPRIV
ovs-ofctl dump-ports-desc $BRPUB


# Add ARP to the priv bridge
ovs-ofctl add-flow $BRPRIV priority=10,in_port=$RP_PRIV_LEG_DEV,arp,action=normal
ovs-ofctl add-flow $BRPRIV priority=10,in_port=$BRPRIV,arp,action=normal
#ovs-ofctl add-flow $BRPRIV priority=10,in_port=$RP_PRIV_LEG_DEV,icmp,action=normal
#ovs-ofctl add-flow $BRPRIV priority=10,in_port=$BRPRIV,icmp,action=normal
ovs-ofctl add-flow $BRPRIV priority=50,in_port=$RP_PRIV_PATCH_PORT,arp,action=drop
ovs-ofctl add-flow $BRPRIV priority=50,in_port=$RP_PRIV_PATCH_PORT,ip6,action=drop
ovs-ofctl add-flow $BRPRIV priority=50,in_port=$RP_PRIV_PATCH_PORT,dl_dst=ff:ff:ff:ff:ff:ff,action=drop


# Add ARP to the pub bridge
ovs-ofctl add-flow $BRPUB priority=10,in_port=$BRPUB,arp,action=normal
ovs-ofctl add-flow $BRPUB priority=10,in_port=$RP_PUB_LEG_DEV,arp,action=normal
#ovs-ofctl add-flow $BRPUB priority=10,in_port=$BRPUB,icmp,action=normal
#ovs-ofctl add-flow $BRPUB priority=10,in_port=$RP_PUB_LEG_DEV,icmp,action=normal
ovs-ofctl add-flow $BRPUB priority=50,in_port=$RP_PUB_PATCH_PORT,arp,action=drop
ovs-ofctl add-flow $BRPUB priority=50,in_port=$RP_PUB_PATCH_PORT,ip6,action=drop
ovs-ofctl add-flow $BRPUB priority=50,in_port=$RP_PUB_PATCH_PORT,dl_dst=ff:ff:ff:ff:ff:ff,action=drop

# dec_ttl not used currently

# Only forwarding, no NAT'ing.
if [ $MODE = FORWARDING ]
then
	ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_LEG_DEV,udp,nw_dst=$GS_PRIV_ADDR,action=$RP_PUB_PATCH_PORT
	ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,nw_dst=$GS_PRIV_ADDR,action=mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$GS_PRIV_MAC,$RP_PRIV_LEG_DEV
	ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_LEG_DEV,udp,nw_dst=$GC_PUB_ADDR,action=$RP_PRIV_PATCH_PORT
	ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_PATCH_PORT,udp,nw_dst=$GC_PUB_ADDR,action=mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$GC_PUB_MAC,$RP_PUB_LEG_DEV
# Forwarding, and NAT'ing the source address.
elif [ $MODE = "FORWARDING_RP" ]
then
	for ((i = 0; i < $NUM_SESSIONS; i++)); do
		GC_PORT=$(($GC_PORT_START+$i))
		RP_PORT=$(($RP_PORT_START+$i))
		GS_PORT=$(($GS_PORT_START+$i))
		
		# Add the pub side of the flows
		ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_LEG_DEV,udp,nw_dst=$RP_PUB_LEG_ADDR,tp_dst=$RP_PORT,action=mod_nw_dst=$GS_PRIV_ADDR,mod_tp_dst=$GS_PORT,$RP_PUB_PATCH_PORT
		ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,nw_dst=$GS_PRIV_ADDR,tp_dst=$GS_PORT,action=mod_nw_src=$RP_PRIV_LEG_ADDR,mod_tp_src=$RP_PORT,mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$GS_PRIV_MAC,$RP_PRIV_LEG_DEV

		# Add the priv _side of the flows
		ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_LEG_DEV,udp,nw_dst=$RP_PRIV_LEG_ADDR,tp_dst=$RP_PORT,action=mod_nw_dst=$GC_PUB_ADDR,mod_tp_dst=$GC_PORT,$RP_PRIV_PATCH_PORT
		ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_PATCH_PORT,udp,nw_dst=$GC_PUB_ADDR,tp_dst=$GC_PORT,action=mod_nw_src=$RP_PUB_LEG_ADDR,mod_tp_src=$RP_PORT,mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$GC_PUB_MAC,$RP_PUB_LEG_DEV
	done
fi

echo "$BRPRIV"

ovs-ofctl dump-flows $BRPRIV

echo "$BRPUB"
ovs-ofctl dump-flows $BRPUB

#ovs-vsctl show
#ip -o a show $ONE_LINE_DEV
#ip -o a show $BRPUB
#ip -o a show $BRPRIV

exit 0

