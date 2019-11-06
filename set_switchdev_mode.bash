#!/bin/sh

NIC=${1:?param 1 NIC}
NUM_VFS=${2:?param 2 num VFs}

function unbind_vfs() {
    local nic=${1:-$NIC}
    for i in `ls -1d /sys/class/net/$nic/device/virt*`; do
        vfpci=$(basename `readlink $i`)
        if [ -e /sys/bus/pci/drivers/mlx5_core/$vfpci ]; then
            echo "unbind $vfpci"
            echo $vfpci > /sys/bus/pci/drivers/mlx5_core/unbind
        fi
    done
}

function bind_vfs() {
    local nic=${1:-$NIC}
    for i in `ls -1d /sys/class/net/$nic/device/virt*`; do
        vfpci=$(basename `readlink $i`)
        if [ ! -e /sys/bus/pci/drivers/mlx5_core/$vfpci ]; then
            echo "bind vf $vfpci"
            echo $vfpci > /sys/bus/pci/drivers/mlx5_core/bind
        fi
    done
    # sometimes need half a second for netdevs to appear.
    sleep 0.5
}


function switchdev_mode() {

        echo "switchdev_mode $1"
	local nic=${1:-$NIC}
        local pci=$(basename `readlink /sys/class/net/$nic/device`)

        devlink dev eswitch set pci/$pci mode switchdev || fail "Failed to set mode $1"

        sleep 2
}



echo "Starting..."
echo "set sriov num"
echo 0 >  /sys/class/net/$NIC/device/sriov_numvfs
echo $NUM_VFS >  /sys/class/net/$NIC/device/sriov_numvfs
unbind_vfs 
switchdev_mode 
bind_vfs 
ip link | grep DOWN | grep enp.* | cut -d: -f2 | xargs -I {} ip link set dev {} up


