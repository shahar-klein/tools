#!/bin/bash


GS_PRIV_ADDR=7.7.7.9
RP_PRIV_LEG_ADDR=7.7.7.5
RP_PRIV_LEG_DEV=ens5
RP_PUB_LEG_ADDR=9.9.9.6
RP_RIV_LEG_DEV=ens6
GC_PUB_ADDR=9.9.9.10
ONE_LINE_DEV=enp132s0
BRPUB=brpub
BRPTIV=brpriv


OVS_RP_BR=br-rp


#cleanup
ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br

ovs-vsctl add-br $OVS_RP_BR
ovs-vsctl add-port $OVS_RP_BR $BRPUB -- set Interface $BRPUB type=internal
ovs-vsctl add-port $OVS_RP_BR $BRPRIV -- set Interface $BRPRIV type=internal
ovs-vsctl add-port $OVS_RP_BR $ONE_LINE_DEV

ip a add dev $BRPUB $RP_PUB_LEG_ADDR/24 
ip l set dev $BRPUB up
ip a add dev $BRPRIV $RP_PRIV_LEG_ADDR/24 
ip l set dev $BRPRIV up
ovs-ofctl add-flow $OVS_RP_BR priority=10,in_port=$ONE_LINE_DEV,arp,action=normal
ovs-ofctl add-flow $OVS_RP_BR priority=10,in_port=$BRPUB,arp,action=normal
ovs-ofctl add-flow $OVS_RP_BR priority=10,in_port=$BRPRIV,arp,action=normal
ovs-ofctl add-flow $OVS_RP_BR priority=100,in_port=$ONE_LINE_DEV,udp,nw_dst=$RP_PRIV_LEG_ADDR,action=mod_nw_dst=$GC_PUB_ADDR,$ONE_LINE_DEV


ovs-ofctl add-flow $OVS_RP_BR priority=100,in_port=priv-patch,udp,nw_dst=7.7.7.9,action=mod_dl_src=ec:0d:9a:d8:ff:16,mod_dl_dst=50:6b:4b:fb:ee:ea,mod_nw_src=7.7.7.5,dec_ttl,ens5

ovs-ofctl add-flow $OVS_RP_BR priority=10,in_port=brpub,arp,action=normal
ovs-ofctl add-flow $OVS_RP_BR priority=10,in_port=ens6,arp,action=normal
ovs-ofctl add-flow $OVS_RP_BR priority=50,in_port=pub-patch,arp,action=drop
ovs-ofctl add-flow $OVS_RP_BR priority=100,in_port=ens6,udp,nw_dst=9.9.9.6,action=mod_nw_dst=7.7.7.9,pub-patch
ovs-ofctl add-flow $OVS_RP_BR priority=100,in_port=pub-patch,udp,nw_dst=9.9.9.10,action=mod_nw_src=9.9.9.6,mod_dl_src=ec:0d:9a:d8:ff:17,mod_dl_dst=98:03:9b:16:47:16,dec_ttl,ens6





ovs-vsctl show
ip -o a show $ONE_LINE_DEV
ip -o a show $BRPUB
ip -o a show $BRPRIV




exit 0

