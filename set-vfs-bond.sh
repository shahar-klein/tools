#!/bin/sh

NIC1=${1:?param 1 NIC1}
NIC2=${2:?param 2 NIC2}

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
        local nic=${1}
        local pci=$(basename `readlink /sys/class/net/$nic/device`)

        devlink dev eswitch set pci/$pci mode switchdev || fail "Failed to set mode $1"

        sleep 2
}


# start fresh
echo "Clean up"
ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br
echo 0 > /sys/class/net/$NIC1/device/sriov_numvfs
echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs
ip link del inf0 > /dev/null 2>&1
ip link del inf1 > /dev/null 2>&1
ip link del bond0 > /dev/null 2>&1


echo "Starting..."
echo "set sriov num"
echo 8 > /sys/class/net/$NIC1/device/sriov_numvfs
echo 8 > /sys/class/net/$NIC2/device/sriov_numvfs
bash ./set-macs.sh $NIC1
bash ./set-macs.sh $NIC2
unbind_vfs $NIC1
unbind_vfs $NIC2
switchdev_mode $NIC1
switchdev_mode $NIC2
bind_vfs $NIC1
bind_vfs $NIC2



#create bond0
BOND=bond0
ip link add name $BOND type bond mode active-backup miimon 100

#attach vfs to bond
VF1PF1=${NIC1}f3
VF1PF2=${NIC2}f3
ip link set dev $VF1PF1 master $BOND
ip link set dev $VF1PF2 master $BOND
ip link set dev $VF1PF1 up
ip link set dev $VF1PF2 up
ip link set dev $BOND up

#create bridge br-bond0 and attach bond device
ovs-vsctl add-br br-bond0
ovs-vsctl add-port br-bond0 $BOND

#create phy-NIC1
#attach NIC1 
#attach repOfVF1NIC1
echo create phy-NIC1
echo attach NIC1 
echo attach repOfVF1NIC1
REP1PF1=${NIC1}_2
BRPHYNIC1=br-${NIC1}
ovs-vsctl add-br $BRPHYNIC1
ovs-vsctl add-port $BRPHYNIC1 $REP1PF1
ovs-vsctl add-port $BRPHYNIC1 $NIC1
ip link set dev $REP1PF1 up

#create phy-NIC2
#attach NIC2
#attach repOfVF1NIC2
echo create phy-NIC2
echo attach NIC2
echo attach repOfVF1NIC2
REP1PF2=${NIC2}_2
BRPHYNIC2=br-${NIC2}
ovs-vsctl add-br $BRPHYNIC2
ovs-vsctl add-port $BRPHYNIC2 $REP1PF2
ovs-vsctl add-port $BRPHYNIC2 $NIC2
ip link set dev $REP1PF2 up


#create infra endpoint and attach to br-bond0
echo create infra endpoint and attach to br-bond0
ip link add inf0 type veth peer name inf1
ip link set dev inf0 up
ip link set dev inf1 up
ovs-vsctl add-port br-bond0 inf0
ip addr add 20.20.20.101/24 dev inf1

