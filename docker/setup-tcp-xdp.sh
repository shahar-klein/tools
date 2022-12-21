#!/usr/bin/bash


# IT is possible that configuration already exists in this DPU,
# e.g when this pod is scheduled, the DPU has already been 
# provisioned by NM.  If the xdp NS is around then assume
# it is set; the liveliness probe can take care of checking
# if it is configured correctly.

echo "I am setup-tcp-xdp.sh[$0] PID: $$ at `date`" > /root/setup-tcp-xdp_call.$$

ip netns list | grep -q 'xdp_ns' && { echo "XDP already configured exist"; exit 0; }

echo "Configuring TCP XDP pre-reqs"

hostname=$(ovs-vsctl get open . external_ids:hostname)
if [[ "${hostname}" == "" ]]; then
        echo "Hostname not found"
        exit 1
fi
echo "Found hostname $hostname"

# Much simpler to do it this way instead of getting from env or API server etc.
# since it is pretty fixed in terms of XDP configurations on DPUs
if [[ "${hostname}" == *"dpu-1"* ]]; then
        echo "DPU1"
        iface_name=p0
        ovs_br=brbond0
# We don't need to do this on DPU-3, but we do it currently
# so keep it that way.
else
        echo "not DPU1"
        iface_name=p1
        ovs_br=brp1
fi
sfnum=0

# Verify the bridge and interface exist
ovs-vsctl list-br | grep -q "${ovs_br}" || { echo "ERROR: Bridge ${ovs_br} does not exist"; exit 1; }
ip li show ${iface_name} || { echo "ERROR: Interface ${iface_name} does not exist"; exit 1; }

# To ensure the calculated macs are unique, calculate the last octet based on the interface and SF number.
case "$iface_name" in
 p0) iface_mac_offset=0 ;;
 p1) iface_mac_offset=100 ;;
 *)  iface_mac_offset=200 ;;
esac
let "generated_mac_idx = $iface_mac_offset + $sfnum"
echo "Configuring SF ${sfnum} for ${iface_name} on ${ovs_br} with mac idx ${generated_mac_idx}"

# Grab the device ID of the physical interface where we'll run the SF
iface_dev_id=$(basename $(readlink /sys/class/net/${iface_name}/device)) || { echo "ERROR: Failed to lookup ${iface_name} PCI ID"; exit 1; }

echo "Found ${iface_name} at ${iface_dev_id}"
echo "Current sf_json: $(/sbin/mlnx-sf -a show --json)"

# Check for an existing SF
my_sf_json=$(/sbin/mlnx-sf -a show --json | jq ".[] | select(.device == \"${iface_dev_id}\" and .sfnum == ${sfnum})")
if [[ "${my_sf_json}" == "" ]]; then
    echo "WARNING: No existing SF found, will create one..."
    sys_uuid=$(dmidecode -s system-uuid) || { echo "ERROR: Failed to lookup system-uuid"; exit 1; }
    mac_base="0a:$(echo ${sys_uuid} | sed -n 's/-//gp' | sed -n 's/\(..\)/\1:/gp' | cut -d: -f1-4)"
    echo "Using base mac ${mac_base}"
    sf_mac=$(printf "%s:%.2x" ${mac_base} ${generated_mac_idx})
    echo "Creating new SF on ${iface_dev_id} with mac ${sf_mac}"
    /sbin/mlnx-sf --action create --device ${iface_dev_id} --sfnum ${sfnum} --hwaddr ${sf_mac} || { echo "ERROR: Failed to create SF"; exit 1; }
    echo "Sleeping for 5s udev to settle..."
    sleep 5
    my_sf_json=$(/sbin/mlnx-sf -a show --json | jq ".[] | select(.device == \"${iface_dev_id}\" and .sfnum == ${sfnum})")
    if [[ "${my_sf_json}" == "" ]]; then
        echo "ERROR: Still failed to lookup my SF after creating it"
        exit 1
    fi
    echo "New SF json: ${my_sf_json}"

else
    echo "Found existing SF ${my_sf_json}"
fi

# Grab SF details needed to setup NS
netdev=$(   echo "${my_sf_json}" | jq --raw-output ".netdev")       # en3f1pf1sf0 : AKA "corresponding representor"
sf_netdev=$(echo "${my_sf_json}" | jq --raw-output ".sf_netdev")    # enp3s0f1s0  : AKA "P1 SF"

echo "Got netdev=${netdev} and sf_netdev=${sf_netdev} from SF json"

if [[ "${sf_netdev}" == "" || "${netdev}" == "" ]]; then
    echo "ERROR: Failed to find netdev and/or sf_netdev: \"${netdev}\" and/or \"${sf_netdev}\" in mlnx-sf output: ${my_sf_json}"
    exit 1
fi

if [[ "${netdev}" != "xdp_sf" ]]; then
    echo "Renaming SF rep ${netdev} to xdp_sf. Downing ifc..."
    ifconfig ${netdev} down
    echo "Down RC: $? Renaming..."
    ip link set ${netdev} name xdp_sf
    echo "Rename RC: $? UPing..."
    ifconfig xdp_sf up
    echo "Up RC: $?"
    netdev=xdp_sf
fi

# Cleanup the default mlnx sf config
cleared_by=$(realpath "$0")
echo "# Cleared by ${cleared_by}" > /etc/mellanox/mlnx-sf.conf

# Create netns if needed
ip netns list | grep -q 'xdp_ns' || ip netns add xdp_ns

# Configure forwarding et. al. in the XDP namespace
ip netns exec xdp_ns  sysctl -w net.ipv4.conf.all.forwarding=1
ip netns exec xdp_ns /sbin/sysctl -w net/ipv4/tcp_timestamps=1
ip netns exec xdp_ns /sbin/sysctl -w net/netfilter/nf_conntrack_tcp_loose=0

# Add physical port's SF to xdp_ns
ip link set netns xdp_ns ${sf_netdev} || echo "ERROR: Failed to move ${sf_netdev} to xdp_ns namespace $?"

# Add the corresponding representor to the OVS bridge brpX
ovs-vsctl --may-exist add-port ${ovs_br} ${netdev}

# Create a veth pair with one end on brpX and another in xdp_ns, ignoring errors if they already exist
ip link add dev veth_fw type veth peer name xdp_veth || echo "ERROR: Failed to create a VETH Pair $?"
ip link set dev veth_fw netns xdp_ns  || echo "ERROR: Failed to move veth_fw link to xdp_ns namespace $?"
ovs-vsctl --may-exist add-port ${ovs_br} xdp_veth

# Configure the XDP  interfaces:
ip netns exec xdp_ns ifconfig veth_fw promisc up || echo "ERROR: Setting veth_fw promisc UP in xdp_ns failed with $?"
ip netns exec xdp_ns ifconfig ${sf_netdev} promisc up || echo "ERROR: Setting ${sf_netdev} promisc UP in xdp_ns failed with $?"
ip link set dev xdp_veth up || echo "ERROR: Setting xdp_veth UP failed with $?"
ip netns exec xdp_ns ip link set lo up || echo "ERROR: Setting lo up in xdp_ns failed with $?"

# BMA-304
#for portname in ${netdev} xdp_veth; do
#    ovs-ofctl mod-port ${ovs_br} ${portname} no-flood || echo "ERROR: Configure no-flood on ${portname} failed with $?"
#done

# Enable XDP feature
ip netns exec xdp_ns ip link set ${sf_netdev} xdp object /opt/mellanox/xdp/lib64/xdp.o section xdp/syncookie
ip netns exec xdp_ns ethtool --set-priv-flags ${sf_netdev} tx_xdp_hw_checksum on

# Configure iptables rules (for syn proxy)
ip netns exec xdp_ns iptables -t raw -I PREROUTING -i ${sf_netdev} -p tcp -m tcp --syn  -j CT --notrack
ip netns exec xdp_ns iptables -A FORWARD -i ${sf_netdev} -p tcp -m tcp  -m state --state INVALID,UNTRACKED -j SYNPROXY --sack-perm --timestamp --wscale 2 --mss 1000
ip netns exec xdp_ns iptables -A FORWARD -m state --state INVALID -j DROP

exit 0
