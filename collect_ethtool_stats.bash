#!/bin/bash
set -u

sleep_duration=$1
RP_PRIV_LEG_DEV=$2
RP_PUB_LEG_DEV=$3
RESULTS_LOG_DIR=$4

rm -rf $RESULTS_LOG_DIR/*


BASE_RX_BYTES=`ethtool -S $RP_PRIV_LEG_DEV | grep "rx_bytes:" | awk '{print  $2}'`
BASE_TX_BYTES=`ethtool -S $RP_PUB_LEG_DEV | grep "tx_bytes:" | awk '{print  $2}'`
BASE_RX_DROPPED=`ethtool -S $RP_PRIV_LEG_DEV | grep "rx_out_buffer:" | awk '{print  $2}'`
BASE_TX_DROPPED=`ethtool -S $RP_PUB_LEG_DEV | grep "tx_queue_dropped:" | awk '{print  $2}'`
for (( dur=1; dur<=$DURATION; dur++ ))
do

        # RX bytes
        rx_bytes=`ethtool -S $RP_PRIV_LEG_DEV | grep "rx_bytes:" | awk '{print  $2}'`
        echo $dur $((rx_bytes-BASE_RX_BYTES)) >> $RESULTS_LOG_DIR/${RP_PRIV_LEG_DEV}.tput

        # TX bytes
        tx_bytes=`ethtool -S $RP_PUB_LEG_DEV | grep "tx_bytes:" | awk '{print  $2}'`
        echo $dur $((tx_bytes-BASE_TX_BYTES)) >> $RESULTS_LOG_DIR/${RP_PUB_LEG_DEV}.tput

        # RX buffer overruns
        rx_dropped=`ethtool -S $RP_PRIV_LEG_DEV | grep "rx_out_buffer:" | awk '{print  $2}'`
        echo $dur $((rx_dropped-BASE_RX_DROPPED)) >> $RESULTS_LOG_DIR/${RP_PRIV_LEG_DEV}.dropped

        # TX drops
        tx_dropped=`ethtool -S $RP_PUB_LEG_DEV | grep "rx_out_buffer:" | awk '{print  $2}'`
        echo $dur $((tx_dropped-BASE_TX_DROPPED)) >> $RESULTS_LOG_DIR/${RP_PUB_LEG_DEV}.dropped

        BASE_RX_BYTES=rx_bytes
        BASE_TX_BYTES=tx_bytes
        BASE_RX_DROPPED=rx_dropped
        BASE_TX_DROPPED=tx_dropped
        sleep $sleep_duration
done
