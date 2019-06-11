#!/bin/bash

GS_PRIV_ADDR=7.7.7.9
GS_PRIV_MAC=50:6b:4b:fb:ee:ea
RP_PRIV_LEG_ADDR=7.7.7.5
RP_PRIV_LEG_MAC=86:46:d4:3d:1e:9a
RP_PRIV_LEG_DEV=ens5
RP_PUB_LEG_ADDR=9.9.9.6
RP_PUB_LEG_MAC=ee:56:dc:c9:8e:4a
RP_PUB_LEG_DEV=ens6
RP_PRIV_PATCH_PORT=priv-patch
RP_PUB_PATCH_PORT=pub-patch
GS_PUB_ADDR=9.9.9.10
GS_PUB_MAC=98:03:9b:16:47:16
BRPUB=brpub
BRPRIV=brpriv


#cleanup
ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br

ip l set dev $RP_PRIV_LEG_DEV up
ip l set dev $RP_PUB_LEG_DEV up

ovs-vsctl add-br $BRPRIV
ovs-vsctl add-port $BRPRIV $RP_PRIV_LEG_DEV

ovs-vsctl add-br $BRPUB
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
ovs-ofctl add-flow $BRPRIV priority=50,in_port=$RP_PRIV_PATCH_PORT,dl_dst=ff:ff:ff:ff:ff:ff,action=drop


# Add ARP to the pub bridge
ovs-ofctl add-flow $BRPUB priority=10,in_port=$BRPUB,arp,action=normal
ovs-ofctl add-flow $BRPUB priority=10,in_port=$RP_PUB_LEG_DEV,arp,action=normal
ovs-ofctl add-flow $BRPUB priority=50,in_port=$RP_PUB_PATCH_PORT,arp,action=drop
ovs-ofctl add-flow $BRPUB priority=50,in_port=$RP_PUB_PATCH_PORT,dl_dst=ff:ff:ff:ff:ff:ff,action=drop

# Add the priv side of the flows
ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_LEG_DEV,udp,nw_dst=$RP_PRIV_LEG_ADDR,action=mod_nw_dst=$GS_PUB_ADDR,$RP_PRIV_PATCH_PORT
# ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,nw_dst=$GS_PRIV_ADDR,action=mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$GS_PRIV_MAC,mod_nw_src=$RP_PRIV_LEG_ADDR,dec_ttl,$RP_PRIV_LEG_DEV
ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,nw_dst=$GS_PRIV_ADDR,action=mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$GS_PRIV_MAC,mod_nw_src=$RP_PRIV_LEG_ADDR,$RP_PRIV_LEG_DEV

# Add the pub side of the flows
ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_LEG_DEV,ip,nw_dst=$RP_PUB_LEG_ADDR,action=mod_nw_dst=$GS_PRIV_ADDR,$RP_PUB_PATCH_PORT
# ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_PATCH_PORT,udp,nw_dst=$GS_PUB_ADDR,action=mod_nw_src=$RP_PUB_LEG_ADDR,mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$GS_PUB_MAC,dec_ttl,$RP_PUB_LEG_DEV
ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_PATCH_PORT,udp,nw_dst=$GS_PUB_ADDR,action=mod_nw_src=$RP_PUB_LEG_ADDR,mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$GS_PUB_MAC,$RP_PUB_LEG_DEV


echo "$BRPRIV"

ovs-ofctl dump-flows $BRPRIV

echo "$BRPUB"
ovs-ofctl dump-flows $BRPUB

#ovs-vsctl show
#ip -o a show $ONE_LINE_DEV
#ip -o a show $BRPUB
#ip -o a show $BRPRIV

exit 0

