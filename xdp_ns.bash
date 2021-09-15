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

XDP_OVSBR=brp1


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
MAC_SF=`cat /sys/class/net/${VETH_OVS_SIDE}/address`
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

BR_INT_PATCH=2

# Give the other end to ovs
ovs-vsctl --may-exist add-port $XDP_OVSBR $VETH_OVS_SIDE
ovs-vsctl --may-exist add-port $XDP_OVSBR $SF_REP

## on $XDP_OVSBR, add the flows ##A

ovs-ofctl del-flows brp1 table=0,in_port=$VETH_OVS_SIDE

#/* Send the packet coming into the RP’s public to the tenant / vlan specific NS */
ovs-ofctl add-flow $XDP_OVSBR table=0,dl_vlan=$VLAN,tcp,in_port=p1,actions=strip_vlan,mod_dl_dst:$MAC_SF,output:$SF_REP

#/* Send the packet from the NS to the RP’s public for the tenant */
ovs-ofctl add-flow -O OpenFlow13 $XDP_OVSBR "table=0,in_port=$VETH_OVS_SIDE,actions=push_vlan:0x8100,set_field:${OF_VLAN}->vlan_vid,output:${BR_INT_PATCH}"

#/* Send the RP’s public to the tenant’s NS */
ovs-ofctl add-flow $XDP_OVSBR table=0,dl_vlan=$VLAN,tcp,in_port=$BR_INT_PATCH,actions=strip_vlan,mod_dl_dst:$MAC_VETH_NS,output:$VETH_OVS_SIDE

#/* Send the packet from the NS to the external client */
ovs-ofctl add-flow -O OpenFlow13 brp1 "table=0,in_port=$SF_REP,actions=push_vlan:0x8100,set_field:$OF_VLAN->vlan_vid,output:p1"





