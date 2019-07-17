#!/bin/bash
set -u

DURATION=$1
sleep_duration=$2
RP_PRIV_LEG_DEV=$3
RP_PUB_LEG_DEV=$4
RESULTS_LOG_DIR=$5
NIC_MODE=$6

rm -f $RESULTS_LOG_DIR/${RP_PRIV_LEG_DEV}.tput
rm -f $RESULTS_LOG_DIR/${RP_PUB_LEG_DEV}.tput
rm -f $RESULTS_LOG_DIR/${RP_PRIV_LEG_DEV}.dropped
rm -f $RESULTS_LOG_DIR/${RP_PUB_LEG_DEV}.dropped


if [ $NIC_MODE = "pt" ]
then
	rxbytes="rx_bytes_phy:"
	txbytes="tx_bytes_phy:"
else
	rxbytes="rx_vport_unicast_bytes:"
	txbytes="tx_vport_unicast_bytes:"
fi

for (( dur=1; dur<=$DURATION; dur++ ))
do

        sleep $sleep_duration
        # RX bytes
        rx_bytes=`ethtool -S $RP_PRIV_LEG_DEV | grep $rxbytes | awk '{print  $2}'`
        tx_bytes=`ethtool -S $RP_PUB_LEG_DEV | grep $txbytes | awk '{print  $2}'`
        rx_dropped=`ethtool -S $RP_PRIV_LEG_DEV | grep "rx_out_of_buffer:" | awk '{print  $2}'`
        tx_dropped=`ethtool -S $RP_PUB_LEG_DEV | grep "tx_queue_dropped:" | awk '{print  $2}'`

        #echo $dur $((rx_bytes-BASE_RX_BYTES)) >> $RESULTS_LOG_DIR/${RP_PRIV_LEG_DEV}.tput
        echo $dur $rx_bytes >> $RESULTS_LOG_DIR/${RP_PRIV_LEG_DEV}.tput

        # TX bytes
        #echo $dur $((tx_bytes-BASE_TX_BYTES)) >> $RESULTS_LOG_DIR/${RP_PUB_LEG_DEV}.tput
        echo $dur $tx_bytes >> $RESULTS_LOG_DIR/${RP_PUB_LEG_DEV}.tput

        # RX buffer overruns
        #echo $dur $((rx_dropped-BASE_RX_DROPPED)) >> $RESULTS_LOG_DIR/${RP_PRIV_LEG_DEV}.dropped
        echo $dur $rx_dropped >> $RESULTS_LOG_DIR/${RP_PRIV_LEG_DEV}.dropped

        # TX drops
        #echo $dur $((tx_dropped-BASE_TX_DROPPED)) >> $RESULTS_LOG_DIR/${RP_PUB_LEG_DEV}.dropped
        echo $dur $tx_dropped >> $RESULTS_LOG_DIR/${RP_PUB_LEG_DEV}.dropped

        #BASE_RX_BYTES=$rx_bytes
        #BASE_TX_BYTES=$tx_bytes
        #BASE_RX_DROPPED=$rx_dropped
        #BASE_TX_DROPPED=$tx_dropped
done
