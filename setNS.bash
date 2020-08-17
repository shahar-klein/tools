#!/bin/bash

NS_NAME=nsInitiator
NS_DEV=enp1s0
NS_IP=30.30.30.20/16

ip netns del $NS_NAME
ip netns add $NS_NAME
ip link set $NS_DEV netns $NS_NAME
ip netns exec $NS_NAME ip link set $NS_DEV up
ip netns exec $NS_NAME ip add add $NS_IP dev $NS_DEV
