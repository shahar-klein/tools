#!/bin/bash

Usage() {
	echo
	echo "usage: $0 DEV1 [ DEV2 ] to examine [ delta T ]"
	echo
	exit 1
}

if [ A$1 = A  ] ; then
	Usage
fi

if [ $1 = "-h" ] ; then
        Usage
fi

DEV1=$1
DEV2=$2

human_bytes() {
	N=$1
	N=$((N*8))
	if [ $N -gt 1000000000 ] ; then
		echo "$(bc<<<"scale=2; $N/(1024*1024*1024)") GB"
		return
	fi
	if [ $N -gt 1000000 ] ; then
		echo "$(bc<<<"scale=2; $N/(1024*1024)") MB"
		return
	fi
	echo "$N bytes"
}



DT=${3:-1}
echo DT=$DT

clear
echo 
echo
echo "               TX	            RX"

while [ 1 ] ; do
RX1D1=`ethtool -S $DEV1 | grep rx_bytes_phy | awk '{print $2}'`
TX1D1=`ethtool -S $DEV1 | grep tx_bytes_phy | awk '{print $2}'`
if [ $DEV2 ] ; then
	RX1D2=`ethtool -S $DEV2 | grep rx_bytes_phy | awk '{print $2}'`
	TX1D2=`ethtool -S $DEV2 | grep tx_bytes_phy | awk '{print $2}'`
fi
sleep $DT
RX2D1=`ethtool -S $DEV1 | grep rx_bytes_phy | awk '{print $2}'`
TX2D1=`ethtool -S $DEV1 | grep tx_bytes_phy | awk '{print $2}'`
if [ $DEV2 ] ; then
	RX2D2=`ethtool -S $DEV2 | grep rx_bytes_phy | awk '{print $2}'`
	TX2D2=`ethtool -S $DEV2 | grep tx_bytes_phy | awk '{print $2}'`
fi

DRXD1=`human_bytes $(((RX2D1-RX1D1)/DT))`
DTXD1=`human_bytes $(((TX2D1-TX1D1)/DT))`
echo   "$DEV1      $DTXD1            $DRXD1"
if [ $DEV2 ] ; then
	DRXD2=`human_bytes $(((RX2D2-RX1D2)/DT))`
	DTXD2=`human_bytes $(((TX2D2-TX1D2)/DT))`
	echo  "$DEV2      $DTXD2            $DRXD2"
	echo -e "\033[3A"
else
	echo -e "\033[2A"
fi
done

