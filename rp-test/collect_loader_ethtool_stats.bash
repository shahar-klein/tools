#!/bin/bash
set -u

DURATION=$1
sleep_duration=$2
LOADER_LEG_DEV=$3
RESULTS_LOG_DIR=$4

rm -f $RESULTS_LOG_DIR/${LOADER_LEG_DEV}.tput

txbytes="tx_bytes_phy:"

for (( dur=1; dur<=$DURATION; dur++ ))
do

        sleep $sleep_duration
        # RX bytes
        tx_bytes=`ethtool -S $LOADER_LEG_DEV | grep $txbytes | awk '{print  $2}'`

        # TX bytes
        echo $dur $tx_bytes >> $RESULTS_LOG_DIR/${LOADER_LEG_DEV}.tput

done
