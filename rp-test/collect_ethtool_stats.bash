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
rm -f $RESULTS_LOG_DIR/${RP_PRIV_LEG_DEV_HA}.tput
rm -f $RESULTS_LOG_DIR/${RP_PUB_LEG_DEV_HA}.tput
rm -f $RESULTS_LOG_DIR/${RP_PRIV_LEG_DEV_HA}.dropped
rm -f $RESULTS_LOG_DIR/${RP_PUB_LEG_DEV_HA}.dropped


if [ $NIC_MODE = "pt" ]
then
	rxbytes="rx_bytes_phy:"
	txbytes="tx_bytes_phy:"
else
	rxbytes="rx_vport_unicast_bytes:"
	txbytes="tx_vport_unicast_bytes:"
fi

half_duration=$((DURATION/2))
for (( dur=1; dur<=$DURATION; dur++ ))
do

        sleep $sleep_duration
        # RX bytes
        rx_bytes=`ethtool -S $RP_PRIV_LEG_DEV | grep $rxbytes | awk '{print  $2}'`
        tx_bytes=`ethtool -S $RP_PUB_LEG_DEV | grep $txbytes | awk '{print  $2}'`
        rx_dropped=`ethtool -S $RP_PRIV_LEG_DEV | grep "rx_out_of_buffer:" | awk '{print  $2}'`
        tx_dropped=`ethtool -S $RP_PUB_LEG_DEV | grep "tx_queue_dropped:" | awk '{print  $2}'`

        echo $dur $rx_bytes >> $RESULTS_LOG_DIR/${RP_PRIV_LEG_DEV}.tput

        # TX bytes
        echo $dur $tx_bytes >> $RESULTS_LOG_DIR/${RP_PUB_LEG_DEV}.tput

        # RX buffer overruns
        echo $dur $rx_dropped >> $RESULTS_LOG_DIR/${RP_PRIV_LEG_DEV}.dropped

        # TX drops
        echo $dur $tx_dropped >> $RESULTS_LOG_DIR/${RP_PUB_LEG_DEV}.dropped

	# Let the backup take over
	if [ $NIC_MODE = "ha" ]; then
        	rx_bytes_ha=`ethtool -S $RP_PRIV_LEG_DEV_HA | grep $rxbytes | awk '{print  $2}'`
        	tx_byte_ha=`ethtool -S $RP_PUB_LEG_DEV_HA | grep $txbytes | awk '{print  $2}'`
        	rx_dropped_ha=`ethtool -S $RP_PRIV_LEG_DEV_HA | grep "rx_out_of_buffer:" | awk '{print  $2}'`
        	tx_dropped_ha=`ethtool -S $RP_PUB_LEG_DEV_HA | grep "tx_queue_dropped:" | awk '{print  $2}'`
        	echo $dur $rx_bytes_ha >> $RESULTS_LOG_DIR/${RP_PRIV_LEG_DEV_HA}.tput
        	echo $dur $tx_bytes_ha >> $RESULTS_LOG_DIR/${RP_PUB_LEG_DEV_HA}.tput
        	echo $dur $rx_dropped_ha >> $RESULTS_LOG_DIR/${RP_PRIV_LEG_DEV_HA}.dropped
        	echo $dur $tx_dropped_ha >> $RESULTS_LOG_DIR/${RP_PUB_LEG_DEV_HA}.dropped
		if [ $dur -eq $half_duration ]; then
			ifconfig $RP_PRIV_LEG_DEV down; ifconfig $RP_PUB_LEG_DEV down
		fi
	fi
        #BASE_RX_BYTES=$rx_bytes
        #BASE_TX_BYTES=$tx_bytes
        #BASE_RX_DROPPED=$rx_dropped
        #BASE_TX_DROPPED=$tx_dropped
done
