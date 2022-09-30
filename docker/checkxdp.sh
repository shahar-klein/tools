#!/usr/bin/bash

#Check if the XDP parameters are configured correctly


nsveth=veth_fw

# Check that the ns is around. Currentl we configure on
# dpu-1,2 and 3. But we don't use the one on 03, else
# we could skip 03..

ip netns list | grep -q 'xdp_ns' || { echo "ERROR: XDP NS does not exist"; exit 1; }

hostname=$(ovs-vsctl get open . external_ids:hostname)
if [[ "${hostname}" == "" ]]; then
        echo "Hostname not found"
        exit 1
fi
echo "Found hostname $hostname"

# Much simpler to do it this way instead of getting from env or API server etc.
# since it is pretty fixed in terms of XDP configurations on DPUs
# XXX-Check where to get the sfdev from, given this devices is already in the NS
if [[ "${hostname}" == *"dpu-1"* ]]; then
        echo "DPU1"
        iface_name=p0
        ovs_br=brbond0
        sfdev=enp3s0f0s0
# We don't need to do this on DPU-3, but we do it currently
# so keep it that way.
else
        echo "not DPU1"
        iface_name=p1
        ovs_br=brp1
        sfdev=enp3s0f1s0
fi
sfnum=0

##iface_dev_id=$(basename $(readlink /sys/class/net/${iface_name}/device)) || { echo "ERROR: Failed to lookup ${iface_name} PCI ID"; ip netns del xdp_ns; exit 1; }
iface_dev_id=$(basename $(readlink /sys/class/net/${iface_name}/device)) || { echo "ERROR: Failed to lookup ${iface_name} PCI ID"; exit 1; }

# We'll delete the xdp_ns on error so that the restart reconfigures it. 
my_sf_json=$(/sbin/mlnx-sf -a show --json | jq ".[] | select(.device == \"${iface_dev_id}\" and .sfnum == ${sfnum})")
if [[ "${my_sf_json}" == "" ]]; then
        echo "ERROR: SF not found"
        # ip netns del xdp_ns
        exit 1
fi

netdev=$(echo "${my_sf_json}" | jq --raw-output ".netdev")       # representor

sf_netdev=$(echo "${my_sf_json}" | jq --raw-output ".sf_netdev") # SF device
if [[ "${sf_netdev}" != "" ]]; then
        echo "ERROR: SF Device still on host"
        # ip netns del xdp_ns
        exit 1
fi

# Check if the NS has the SF dev and veth device

##ip netns exec xdp_ns ip li show dev ${sfdev} || { echo "ERROR: SF not found in XDP namespace"; ip netns del xdp_ns; exit 1; }
ip netns exec xdp_ns ip li show dev ${sfdev}  >> /dev/null || { echo "ERROR: SF not found in XDP namespace"; exit 1; }

# check if  xdp is set on the sf device and tx_xdp_hw_checksum.
##ip netns exec xdp_ns ip li show ${sfdev} | grep "prog/xdp" >> /dev/null || { echo "ERROR: xdp not configured for ${sfdev}"; ip netns del xdp_ns; exit 1; }
ip netns exec xdp_ns ip li show ${sfdev} | grep "prog/xdp" >> /dev/null || { echo "ERROR: xdp not configured for ${sfdev}"; exit 1; }

value=$(ip netns exec xdp_ns ethtool --show-priv-flags ${sfdev}  | grep tx_xdp_hw_checksum | cut -d " " -f3)
if [[ "${value}" != "on" ]]; then
        echo "tx_xdp_hw_checksum not enabled on ${sfdev}"
        # ip netns del xdp_ns
        exit 1
fi


##ip netns exec xdp_ns ip li show dev ${nsveth} ||  { echo "ERROR: Veth not found in XDP namespace"; ip netns del xdp_ns; exit 1; }
ip netns exec xdp_ns ip li show dev ${nsveth} >> /dev/null ||  { echo "ERROR: Veth not found in XDP namespace"; exit 1; }

# Check if ovs has the interfaces configured
##ovs-vsctl list interface ${ovs_br} ${netdev}  || { echo "ERROR: SF port  not found in OVS"; ip netns del xdp_ns; exit 1; }
##ovs-vstl list interface ${ovs_br} xdp_veth || { echo "ERROR: Veth port  not found in OVS"; ip netns del xdp_ns; exit 1; }

ovs-vsctl list interface ${ovs_br} ${netdev}  >> /dev/null || { echo "ERROR: SF port  not found in OVS"; exit 1; }
ovs-vsctl list interface ${ovs_br} xdp_veth >> /dev/null || { echo "ERROR: Veth port  not found in OVS"; exit 1; }

# Check if the loopback is up.
##ip netns exec xdp_ns ip li show dev lo | grep UP >> /dev/null || { echo "ERROR: Loopback not UP in XDP namespace"; ip netns del xdp_ns; exit 1; }
ip netns exec xdp_ns ip li show dev lo | grep UP >> /dev/null || { echo "ERROR: Loopback not UP in XDP namespace"; exit 1; }

# Check sysctl params forwarding, tcp_timestamps and nf_conntrack_tcp_loose and some others like promisc on the interfaces
value=$(ip netns exec xdp_ns  sysctl net.ipv4.conf.all.forwarding | cut -d " " -f3)
if [[ ${value} != 1 ]]; then
        echo "net.ipv4.conf.all.forwarding not set to 1"
        # ip netns del xdp_ns
        exit 1
fi

value=$(ip netns exec xdp_ns  sysctl net/ipv4/tcp_timestamps | cut -d " " -f3)
if [[ ${value} != 1 ]]; then
        echo "net/ipv4/tcp_timestamps not set to 1"
        # ip netns del xdp_ns
        exit 1
fi


value=$(ip netns exec xdp_ns  sysctl net/netfilter/nf_conntrack_tcp_loose | cut -d " " -f3)
if [[ ${value} != 0 ]]; then
        echo "nf_conntrack_tcp_loose not set to 0"
        # ip netns del xdp_ns
        exit 1
fi

# Check the ip table rules. These could be made using more specific checks instead of just grep.
##ip netns exec xdp_ns iptables-save -t raw | grep PREROUTING | grep ${sfdev} | grep SYN  >> /dev/null || { echo "No TCP Prerouting in raw table"; ip netns del xdp_ns; exit 1; }
ip netns exec xdp_ns iptables-save -t raw | grep PREROUTING | grep ${sfdev} | grep SYN  >> /dev/null || { echo "No TCP Prerouting in raw table"; exit 1; }

##ip netns exec xdp_ns iptables -S FORWARD | grep SYNPROXY  >> /dev/null || { echo "No SYNPROXY in Forward filter"; ip netns del xdp_ns; exit 1; }
ip netns exec xdp_ns iptables -S FORWARD | grep SYNPROXY  >> /dev/null || { echo "No SYNPROXY in Forward filter"; exit 1; }

##ip netns exec xdp_ns iptables -S FORWARD | grep DROP  >> /dev/null || { echo "No DROP in Forward filter"; ip netns del xdp_ns; exit 1; }
ip netns exec xdp_ns iptables -S FORWARD | grep DROP  >> /dev/null || { echo "No DROP in Forward filter"; exit 1; }

exit 0
