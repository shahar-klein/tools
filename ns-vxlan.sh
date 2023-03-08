#!/bin/bash


ip netns del ns0
ip netns del ns1

ip netns add ns0
ip link add ns0_veth0 type veth peer name ns0_veth1
ip link set ns0_veth0 up
ip link set ns0_veth1 up
ip link set ns0_veth0 netns ns0
ip netns exec ns0 ip add add 70.70.70.100/24 dev ns0_veth0
ip netns exec ns0 ip link set ns0_veth0 up
ip netns exec ns0 ip link add name ns0_vxlan42 type vxlan id 42 dev ns0_veth0 remote 70.70.70.200 dstport 4789
ip netns exec ns0 ip add add 7.7.7.10/24 dev ns0_vxlan42
ip netns exec ns0 ip link set ns0_vxlan42 up




ip netns add ns1
ip link add ns1_veth0 type veth peer name ns1_veth1
ip link set ns1_veth0 up
ip link set ns1_veth1 up
ip link set ns1_veth0 netns ns1
ip netns exec ns1 ip add add 70.70.70.200/24 dev ns1_veth0
ip netns exec ns1 ip link set ns1_veth0 up
ip netns exec ns1 ip link add name ns1_vxlan42 type vxlan id 42 dev ns1_veth0 remote 70.70.70.100 dstport 4789
ip netns exec ns1 ip add add 7.7.7.20/24 dev ns1_vxlan42
ip netns exec ns1 ip link set ns1_vxlan42 up

ip link set br100 down
brctl delbr br100
brctl addbr br100
ip link set br100 up
brctl addif br100 ns0_veth1
brctl addif br100 ns1_veth1

ip netns exec ns1 ping -c 10 7.7.7.10
