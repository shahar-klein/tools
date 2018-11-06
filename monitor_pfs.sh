#!/bin/bash


#init physical devices
PFS=""
VENDOR_MELLANOX="0x15b3"
mdevs=`find /sys/class/net/*/device/vendor | xargs grep $VENDOR_MELLANOX | awk -F "/" '{print $5}'`
for d in $mdevs ; do
        if [[ -d /sys/class/net/$d/device/physfn ]] ; then
                continue
        fi
        PFS=`echo $PFS  $d`
done

declare -A MPFS

for pf in $PFS; do
        STATE=`cat /sys/class/net/$pf/operstate`
        MPFS[${pf}]=$STATE
done

function set_reps() {
        local nic=$1
        local state=$2
        echo set_reps $1 $2
        sriov_numvfs=`cat /sys/class/net/$nic/device/sriov_numvfs`
        for ((i = 0; i < $sriov_numvfs; i++)); do
                if [ "$state" = "up" ] ; then
                        ip link set dev ${nic}_$i up
                else
                        ip link set dev ${nic}_$i down
                fi
        done
}



while [ 1 ] ; do
        for PF in "${!MPFS[@]}"; do
                PREVSTATE=${MPFS[$PF]}
                CURSTATE=`cat /sys/class/net/$PF/operstate`
                #echo "$PF is in  $CURSTATE and was in $PREVSTATE"
                if [ "$CURSTATE" != "$PREVSTATE" ] ; then
                        MPFS[${PF}]=$CURSTATE
                        set_reps $PF $CURSTATE
                fi
        done
        sleep 1
done

