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

read_ethx_val() {
	DEV=$1
	tok=$2
	ethtool -S $DEV | grep $tok | awk '{print $2}'
}

human_bytes() {
	N=$1
	N=$((N*8))
	if [ $N -gt 1000000000 ] ; then
		echo "$(bc<<<"scale=2; $N/(1024*1024*1024)") GiB"
		return
	fi
	if [ $N -gt 1000000 ] ; then
		echo "$(bc<<<"scale=2; $N/(1024*1024)") MiB"
		return
	fi
	echo "$N bytes"
}

human_pps() {
	N=$1
	if [ $N -gt 1000000000 ] ; then
		echo "$(bc<<<"scale=2; $N/(1000*1000*1000)") GPPS"
		return
	fi
	if [ $N -gt 1000000 ] ; then
		echo "$(bc<<<"scale=2; $N/(1000*1000)") MPPS"
		return
	fi
	if [ $N -gt 1000 ] ; then
		echo "$(bc<<<"scale=2; $N/(1000)") KPPS"
		return
	fi
	echo "$N PPS"

}



DT=${3:-1}
echo DT=$DT

clear
echo 
echo
echo "                     TX                                RX"

while [ 1 ] ; do
RX1D1=`read_ethx_val $DEV1 vport_rx_bytes`
TX1D1=`read_ethx_val $DEV1 vport_tx_bytes`
PRX1D1=`read_ethx_val $DEV1 vport_rx_packets`
PTX1D1=`read_ethx_val $DEV1 vport_tx_packets`
if [ $DEV2 ] ; then
	RX1D2=`read_ethx_val $DEV2 vport_rx_bytes`
	TX1D2=`read_ethx_val $DEV2 vport_tx_bytes`
	PRX1D2=`read_ethx_val $DEV2 vport_rx_packets`
	PTX1D2=`read_ethx_val $DEV2 vport_tx_packets`
fi
sleep $DT
RX2D1=`read_ethx_val $DEV1 vport_rx_bytes`
TX2D1=`read_ethx_val $DEV1 vport_tx_bytes`
PRX2D1=`read_ethx_val $DEV1 vport_rx_packets`
PTX2D1=`read_ethx_val $DEV1 vport_tx_packets`
if [ $DEV2 ] ; then
	RX2D2=`read_ethx_val $DEV2 vport_rx_bytes`
	TX2D2=`read_ethx_val $DEV2 vport_tx_bytes`
	PRX2D2=`read_ethx_val $DEV2 vport_rx_packets`
	PTX2D2=`read_ethx_val $DEV2 vport_tx_packets`
fi

DRXD1=`human_bytes $(((RX2D1-RX1D1)/DT))`
DTXD1=`human_bytes $(((TX2D1-TX1D1)/DT))`
PDRXD1=`human_pps $(((PRX2D1-PRX1D1)/DT))`
PDTXD1=`human_pps $(((PTX2D1-PTX1D1)/DT))`

echo   "$DEV1      $DTXD1 [$PDTXD1]            $DRXD1 [$PDRXD1]                                                         "
if [ $DEV2 ] ; then
	DRXD2=`human_bytes $(((RX2D2-RX1D2)/DT))`
	DTXD2=`human_bytes $(((TX2D2-TX1D2)/DT))`
	PDRXD2=`human_pps $(((PRX2D2-PRX1D2)/DT))`
	PDTXD2=`human_pps $(((PTX2D2-PTX1D2)/DT))`
	echo  "$DEV2      $DTXD2 [$PDTXD2]            $DRXD2 [$PDRXD2]                                                "
	echo -e "\033[3A"
else
	echo -e "\033[2A"
fi
done
