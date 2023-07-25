#                             ┌─────────────────────────────────────┐
#┌─────────────┐              │                                     │                ┌──────────────┐
#│             │              │                                     │                │              │
#│             │              │                        20.20.20.1 ──┼────────────────┼─ 20.20.20.20 │
#│             │              │      Router                         │                │              │
#│             │              │                                     │                │  Client      │
#│             │              │                                     │                │              │
#│  server     │              │                                     │                │              │
#│             │              │                                     │                │              │
#│ 30.30.30.30─┼──────────────┼─ 30.30.30.1                         │                │              │
#│             │              │                                     │                │              │
#└─────────────┘              │                                     │                └──────────────┘
#                             │                                     │
#                             │                                     │
#                             └─────────────────────────────────────┘
#
#
#
#
#
#


























#!/bin/bash

set -x

CNS=client_ns
SNS=server_ns
RNS=router_ns


set +e
ip netns del $CNS
set -e
sleep 2
ip netns add $CNS
# Create a veth pair: local and remote
CNS_L_SIDE="cns_L_side"
CNS_R_SIDE="cns_R_side"
ip link add $CNS_R_SIDE type veth peer name $CNS_L_SIDE

set +e
ip netns del $SNS
set -e
sleep 2
ip netns add $SNS
# Create a veth pair
SNS_L_SIDE="sns_L_side"
SNS_R_SIDE="sns_R_side"
ip link add $SNS_R_SIDE type veth peer name $SNS_L_SIDE


set +e
ip netns del $RNS
set -e
sleep 2
ip netns add $RNS

ip link set $CNS_L_SIDE netns $CNS
ip link set $CNS_R_SIDE netns $RNS
ip link set $SNS_L_SIDE netns $SNS
ip link set $SNS_R_SIDE netns $RNS

ip netns exec $CNS ip add add 20.20.20.20/24 dev $CNS_L_SIDE
ip netns exec $RNS ip add add 20.20.20.1/24 dev $CNS_R_SIDE
ip netns exec $SNS ip add add 30.30.30.30/24 dev $SNS_L_SIDE
ip netns exec $RNS ip add add 30.30.30.1/24 dev $SNS_R_SIDE


ip netns exec $CNS ip link set $CNS_L_SIDE up
ip netns exec $RNS ip link set $CNS_R_SIDE up
ip netns exec $RNS ip link set $SNS_R_SIDE up
ip netns exec $SNS ip link set $SNS_L_SIDE up

sleep 3

ip netns exec $CNS ip route add 30.30.30.0/24 via 20.20.20.1 dev $CNS_L_SIDE
ip netns exec $SNS ip route add 20.20.20.0/24 via 30.30.30.1 dev $SNS_L_SIDE


ip netns exec $RNS sysctl -w net.ipv4.conf.all.forwarding=0

#on the router
ip netns exec $SNS iptables -A INPUT -p icmp -j DROP

ip netns exec $RNS ip link set lo up
ip netns exec $RNS ip route del 20.20.20.0/24
ip netns exec $RNS ip route add 20.20.0.0/16 dev cns_R_side
ip netns exec $RNS ip route add 20.20.20.0/24 dev lo



