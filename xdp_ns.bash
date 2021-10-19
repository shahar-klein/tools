#!/bin/bash

set -u
set -e

set -x
#
#
#
#             ┌───────────┐
#             │  RP VM    │
#             │           │
#             └──────────┬┘
#                        │Public leg                                 HOST
#     ───────────────────┼─────────────────────────────────────────────────────────
#                        │                                           ARM
#                        │
#                        │            ┌───────┐              ┌──────────┐
#                        │            │       │  VETH        │          │
#         ┌──────────────┴───────┐    │ BRPF  ├──────────────┤ XDP NS   │
#         │                      ├────┤       │              │          │
#         │   BR-INT             │    │       ├──────────┐ ┌─┤          │
#         │                      │    │       │          │ │ └──────────┘
#         └──────────────────────┘    └────┬──┘          │ │
#                                          │             │ │
#                                          │             │ │
#                                          │        SFREP│ │ SF
#                                         ┌┴─────────────┴─┴─────┐
#                                         │     PF               │
#                                         └──────────┬───────────┘
#                                                    │
#                                                    │
#                                                    │
#                                                    │
#                                            ┌───────┴──────────┐
#                                            │                  │
#                                            │                  │
#                                            │                  │
#                                            │   Gateway        │
#                                            │                  │
#                                            │                  │
#                                            └──────────────────┘
#
#


TENANT=${1:?Need Tenant name}
GW=${2:?Need Gateway}
SUBNET=${3:?Need Subnet}
SF=${4:?Need SF}
SF_REP=${5:?Need SF REP}
VLAN=${6:?Need vlan}

OF_VLAN=$(( 4096 + VLAN ))

XDP_OVSBR=ovsbr1

# Take uplink from bridge
XDP_UPLINK=p0

# Create a ns using some tenant name
NS="${TENANT}-${VLAN}-tcpxdp-ns"
set +e
ip netns del $NS
set -e
sleep 2
ip netns add $NS
# Create a veth pair
VETH_XDP_SIDE="${TENANT}_v_fw"
VETH_OVS_SIDE="${TENANT}_v_ovs"
ip link add $VETH_XDP_SIDE type veth peer name $VETH_OVS_SIDE
sleep 2
ip link set $VETH_OVS_SIDE up
ip link set $VETH_XDP_SIDE up
ip link set $SF up
ip link set $SF_REP up
#MAC_SF=`cat /sys/class/net/${VETH_OVS_SIDE}/address`
MAC_SF=02:e9:b1:75:d0:ac
MAC_VETH_NS=`cat /sys/class/net/${VETH_XDP_SIDE}/address`
# Give one end of veth to ns
ip link set $VETH_XDP_SIDE netns $NS
# Give a SF to the ns
ip link set $SF netns $NS

sleep 2

#ip netns exec $NS ifconfig $VETH_XDP_SIDE promisc up
#ip netns exec $NS ifconfig $SF promisc up


ip netns exec $NS ip link set $VETH_XDP_SIDE up
ip netns exec $NS ip link set $SF up
ip netns exec $NS ip link set $VETH_XDP_SIDE promisc on
ip netns exec $NS ip link set $SF promisc on


# Within ns
# ip ro add 'gateway' dev sf
ip netns exec $NS ip route add ${GW} dev $SF

# ip ro add default via 'gateway' dev sf
ip netns exec $NS ip route add default via $GW dev $SF

# ip ro add 'subnet' via veth
ip netns exec $NS ip route add $SUBNET dev $VETH_XDP_SIDE

BR_INT_PATCH=11

# Give the other end to ovs
ovs-vsctl --may-exist add-port $XDP_OVSBR $VETH_OVS_SIDE
ovs-vsctl --may-exist add-port $XDP_OVSBR $SF_REP

## on $XDP_OVSBR, add the flows ##A

ovs-ofctl del-flows ${XDP_OVSBR} table=0,in_port=$VETH_OVS_SIDE

# Send ARP coming in from the wire to the ns
ovs-ofctl add-flow $XDP_OVSBR  table=0,dl_vlan=$VLAN,arp,in_port=${XDP_UPLINK},actions=normal,strip_vlan,output:$SF_REP

# Send ARP coming in from the patch port to the ns
ovs-ofctl add-flow $XDP_OVSBR table=0,dl_vlan=$VLAN,arp,in_port=$BR_INT_PATCH,actions=normal,strip_vlan,output:$VETH_OVS_SIDE

#/* Send the packet coming into the RP’s public to the tenant / vlan specific NS */
ovs-ofctl add-flow $XDP_OVSBR table=0,dl_vlan=$VLAN,tcp,in_port=${XDP_UPLINK},actions=strip_vlan,mod_dl_dst:$MAC_SF,output:$SF_REP

#/* Send the packet from the NS to the RP’s public for the tenant */
ovs-ofctl add-flow -O OpenFlow13 $XDP_OVSBR "table=0,in_port=$VETH_OVS_SIDE,actions=push_vlan:0x8100,set_field:${OF_VLAN}->vlan_vid,output:${BR_INT_PATCH}"

#/* Send the RP’s public to the tenant’s NS */
ovs-ofctl add-flow $XDP_OVSBR table=0,dl_vlan=$VLAN,tcp,in_port=$BR_INT_PATCH,actions=strip_vlan,mod_dl_dst:$MAC_VETH_NS,output:$VETH_OVS_SIDE

#/* Send the packet from the NS to the external client */
ovs-ofctl add-flow -O OpenFlow13 ${XDP_OVSBR} "table=0,in_port=$SF_REP,actions=push_vlan:0x8100,set_field:$OF_VLAN->vlan_vid,output:${XDP_UPLINK}"


# Set up the XDP namespace

ip netns exec $NS sysctl -w net.ipv4.conf.all.forwarding=1

ip netns exec $NS iptables -t raw -I PREROUTING -i $SF -p tcp -m tcp --syn  -j CT --notrack
ip netns exec $NS iptables -A FORWARD -i $SF -p tcp -m tcp   -m state --state INVALID,UNTRACKED -j SYNPROXY --sack-perm --timestamp --wscale 2 --mss 1460
ip netns exec $NS iptables  -A FORWARD -m state --state INVALID -j DROP

ip netns exec $NS /sbin/sysctl -w net/ipv4/tcp_timestamps=1
ip netns exec $NS /sbin/sysctl -w net/netfilter/nf_conntrack_tcp_loose=0

# ip netns exec $NS ip link set $SF xdp off
# ip netns exec $NS ip link set $SF xdp object /opt/mellanox/xdp/lib64/xdp.o   section xdp/syncookie

ip netns exec $NS  ethtool --set-priv-flags $SF tx_xdp_hw_checksum  on


