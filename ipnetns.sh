
DEV=enp1s0
ip netns  add nsInitiator
ip link set $DEV netns nsInitiator
ip netns exec nsInitiator ip add add 30.30.30.20/16 dev $DEV
ip netns exec nsInitiator ip link set $DEV up
ip netns exec nsInitiator ip r add default  dev $DEV


