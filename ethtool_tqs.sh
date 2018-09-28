#!/bin/bash

Usage() {
	echo
	echo "usage: $0 DEV"
	echo
	exit 1
}

if [ A$1 = A  ] ; then
	Usage
fi

if [ $1 = "-h" ] ; then
        Usage
fi

DEV=$1

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
		echo "$(bc<<<"scale=2; $N/(1000*1000*1000)") packets"
		return
	fi
	if [ $N -gt 1000000 ] ; then
		echo "$(bc<<<"scale=2; $N/(1000*1000)") packets"
		return
	fi
#	if [ $N -gt 1000 ] ; then
#		echo "$(bc<<<"scale=2; $N/(1000)") packets"
#		return
#	fi
	echo "$N packets"

}



DT=${3:-1}
echo DT=$DT
NCORES=`cat /proc/cpuinfo | grep "core id" | wc -l`
clear
echo 
echo
echo "                     TX                                RX"

while [ 1 ] ; do
	for ((i = 0; i < $NCORES; i++)); do
		#TX_{$i}_B=`read_ethx_val $DEV tx${i}_0_packets`
		TX_P_B[$i]=`read_ethx_val $DEV tx${i}_0_packets`
	done
sleep $DT
	for ((i = 0; i < $NCORES; i++)); do
		#TX_{$i}_A=`read_ethx_val $DEV tx${i}_0_packets`
		TX_P_A[$i]=`read_ethx_val $DEV tx${i}_0_packets`
	done

	for ((i = 0; i < $NCORES; i++)); do
		DD=$(((TX_P_A[$i]-TX_P_B[$i])/$DT))
		TX_P_D[$i]=`human_pps $DD`
	done
#DRXD1=`human_bytes $(((RX2D1-RX1D1)/DT))`
#DTXD1=`human_bytes $(((TX2D1-TX1D1)/DT))`
#PDRXD1=`human_pps $(((PRX2D1-PRX1D1)/DT))`
#PDTXD1=`human_pps $(((PTX2D1-PTX1D1)/DT))`

	for ((i = 0; i < $NCORES; i++)); do
		echo tx$i ${TX_P_D[$i]}
	done
echo -e "\033[9A"
done
