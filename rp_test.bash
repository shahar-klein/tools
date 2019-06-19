#!/bin/bash

# TODO
# log() taking a param as a file
# Bandwidth stats in the RP instead of ssh

# 

#
# cleanup
#	clean loader(Game seat), initiator(Game console), rp ip addresses from the relevant devs
#	restart rp
#	
# setup
#	descriptive log name / maybe a dir (and throw all logs into it
#	ip setup if needed
#	rp setup - pininig etc
# init
#	take system readings like ethtool, drop count etc
# run in background
#	noodle
#	10 secs mpstat
#	10 secs traffic on all 3 nodes
# 
# finit
#	take system readings like ethtool, drop count etc

#RP characteristics:
#-------------------
#1. MLNX_TUNE
#       . THRUPUT
#        . 0Loss
#        . PKT Rate
#2. # Channels on the NIC
#       . 8
#3. # CPUS per channel / IRQ Affinity
#       4 CPUs to Rx and the other 4 CPU to Tx
#       8 CPUs (one for each channel on both NICs)
#4. CPU pinning or not
#       . pinned
#       . left dangling
#5. toeplitz or xor
#       . toeplitz
#6. SRIOV / PT
#       . SRIOV [ 1 VF each from the 2 PF]
#       . PT
#
#RP Datapath
#------------
#1. Linux Forward
#2. Linux Forward with IPTables/NAT
#3. OVS Forward (with offload)
#4. OVS Forward with Statless NAT (with offload)
#5. OVS Forward without CT. (for now without offload)
#[3 - 5 : without offloads]



PT_PCI_DEVICE1_BUS=0xb4
PT_PCI_DEVICE1_SLOT=0x00
PT_PCI_DEVICE1_FUNCTION=0x0

PT_PCI_DEVICE2_BUS=0xb4
PT_PCI_DEVICE2_SLOT=0x00
PT_PCI_DEVICE2_FUNCTION=0x1

VF_PCI_DEVICE1_BUS=0xb4
VF_PCI_DEVICE1_SLOT=0x00
VF_PCI_DEVICE1_FUNCTION=0x1

VF_PCI_DEVICE2_BUS=0xb4
VF_PCI_DEVICE2_SLOT=0x00
VF_PCI_DEVICE2_FUNCTION=0x2


PRIV_NET="5.5.5.0/24"
PUB_NET="20.20.20.0/24"

GFN_PUB_PORT_START=8000
GS_PORT_START=10000

RP_PORT_START=5000

LOADER=10.0.0.147
LOADER_DEV=ens2
LOADER_IP=5.5.5.5

INITIATOR=10.0.0.148
INITIATOR_DEV=ens2
INITIATOR_IP=20.20.20.20

RPVM_PT=rp
RPVM_SROV=rp_vf

RPVM=$RPVM_PT
RP=192.168.122.5
RP_PRIV_LEG_IP=5.5.5.1
RP_PRIV_LEG_DEV=enp4s0

NUM_SESSIONS=500
BW_PER_SESSION=20m

RP_PUB_LEG_IP=20.20.20.100
RP_PUB_LEG_DEV=enp7s0


TEST=${1:?test name not set}

# in seconds
DURATION=20
LOG_DURATION=$((DURATION-5))
NUM_CPUS=8
# in seconds
LOG_INTERVAL=1

CPUSTART=1
THROUGHPUT_YRANGE=1000000000
CPU_YRANGE=100
BASE_RX_BYTES=0
BASE_TX_BYTES=0
BASE_RX_DROPPED=0
BASE_TX_DROPPED=0


D=`date +%b-%d-%Y`
LOGDIR=$TEST
LOGDIR+=_$$
LOGDIR+=_$D
echo $LOGDIR
mkdir $LOGDIR
LOG=$LOGDIR/$LOG.main.log

P2KILL=""

# Options are:
# IP_FORWARDING_MULTI_STREAM_THROUGHPUT
# IP_FORWARDING_MULTI_STREAM_PACKET_RATE
# IP_FORWARDING_MULTI_STREAM_0_LOSS - Default

#TEST_PROFILE="IP_FORWARDING_MULTI_STREAM_0_LOSS IP_FORWARDING_MULTI_STREAM_THROUGHPUT IP_FORWARDING_MULTI_STREAM_PACKET_RATE"
TEST_PROFILE="IP_FORWARDING_MULTI_STREAM_0_LOSS"

#TESTS="linux_fwd linux_fwd_nat ovs_fwd ovs_fwd_nat ovs_fwd_ct"
TESTS="linux_fwd"

#NIC_MODES="pt sriov"
NIC_MODES="pt"

#CPU_BINDINGS="dangling pinned"
CPU_BINDINGS="dangling"

#CPU_AFFINITIES="4 8"
CPU_AFFINITIES="4"

log() {
	d=`date +[%d:%m:%y" "%H:%M:%S:%N]`
	echo ${d}:"${@}" >> $LOG
	
}

logCMD() {
	cmd=$@
	output=`$cmd`
	log $cmd
	echo "${output}" >> $LOG
}

cmdBG() {
	$@ >/dev/null 2>&1 &
}

#cmdBG "ssh 10.0.0.147 nohup /root/ws/git/gonoodle/gonoodle -u -s" 


log() {
	d=`date +[%d:%m:%y" "%H:%M:%S:%N]`
	echo ${d}:"${@}" >> $LOG
	
}

logCMD() {
	cmd=$@
	output=`$cmd`
	log $cmd
	echo "${output}" >> $LOG
}

cmdBG() {
	$@ >/dev/null 2>&1 &
}

#cmdBG "ssh 10.0.0.147 nohup /root/ws/git/gonoodle/gonoodle -u -s" 

set -u
set -e

log "`date`  ##Start $TEST##"
log "==================================="
log " "
log " "



get_mac_dev() {
	host=$1
	dev=$2
	mac=`ssh $host ip -o link show $dev | egrep -o 'ether (.*)' | awk '{print $2}'`
	log "get_mac_dev $host $dev => found $mac"
	echo $mac

}


set_ip_dev() {
	host=$1
	dev=$2
	ip=$3
	ssh $host ip a add dev $dev $ip/24
	ssh $host ip link set dev $dev up
	ipset=`ssh $host ip addr show $dev | grep "inet\b" | awk '{print $2}' | cut -d/ -f1`
	log "set_ip_dev $host $dev => set $ipset"
}

flush_ip_dev() {
	host=$1
	dev=$2
	ssh $host ip addr flush dev $dev
	log "flush_ip_dev $host $dev"
}

shutdown_vm() {
	VM=$1

	log "shutting down $VM"

	virsh shutdown $VM
}

startup_vm() {
	VM=$1
	VMIP=$2

	log "starting $VM"

	virsh start $VM
	sleep 2
	local chars=( \| / – \\ )
	local i=0
	while ! timeout 0.3 ping -c 1 -n $VMIP  &> /dev/null ; do
        	        if [ -t 1 ] ; then
                	        i=$((++i%4));
                        	echo "         (${chars[$i]})"
                        	echo -e "\033[2A"
                	fi
                	sleep 0.3

	done
}

reboot_vm() {
	VM=$1
	VMIP=$2

	log "rebooting $VM"

	virsh reboot $VM
	sleep 2
	local chars=( \| / – \\ )
	local i=0
	while ! timeout 0.3 ping -c 1 -n $VMIP  &> /dev/null ; do
        	        if [ -t 1 ] ; then
                	        i=$((++i%4));
                        	echo "         (${chars[$i]})"
                        	echo -e "\033[2A"
                	fi
                	sleep 0.3

	done
}



setup() {
	#reboot_vm $RPVM $RP

	LOADER_DEV_MAC=`get_mac_dev $LOADER $LOADER_DEV`
	flush_ip_dev $LOADER $LOADER_DEV
	set_ip_dev $LOADER $LOADER_DEV $LOADER_IP

	INITIATOR_DEV_MAC=`get_mac_dev $INITIATOR $INITIATOR_DEV`
	flush_ip_dev $INITIATOR $INITIATOR_DEV
	set_ip_dev $INITIATOR $INITIATOR_DEV $INITIATOR_IP
}

setup_vm() {
	RP_PRIV_LEG_MAC=`get_mac_dev $RP $RP_PRIV_LEG_DEV`
	flush_ip_dev $RP $RP_PRIV_LEG_DEV
	set_ip_dev $RP $RP_PRIV_LEG_DEV $RP_PRIV_LEG_IP
	
	RP_PUB_LEG_MAC=`get_mac_dev $RP $RP_PUB_LEG_DEV`
	flush_ip_dev $RP $RP_PUB_LEG_DEV
	set_ip_dev $RP $RP_PUB_LEG_DEV $RP_PUB_LEG_IP
	
	RP_PUB_LEG_MAC=`get_mac_dev $RP $RP_PUB_LEG_DEV`
	flush_ip_dev $RP $RP_PUB_LEG_DEV
	set_ip_dev $RP $RP_PUB_LEG_DEV $RP_PUB_LEG_IP
}


log_before() {
	log ""
	log "Dominfo $RPVM "
	log "========================================="
	logCMD "virsh dominfo $RPVM"

	log ""
	log "PRIV LEG NIC Stats $RP $RP_PRIV_LEG_DEV"
	log "========================================="
	logCMD "ssh $RP ethtool -S $RP_PRIV_LEG_DEV | grep -v ': 0'"

	log ""
	log "PUB LEG NIC Stats $RP $RP_PUB_LEG_DEV"
	log "========================================="
	logCMD "ssh $RP ethtool -S $RP_PUB_LEG_DEV | grep -v ': 0'"

	log "ethtool -a $RP_PRIV_LEG_DEV"
	logCMD "ssh $RP ethtool -a $RP_PRIV_LEG_DEV"
	log "ethtool -c $RP_PRIV_LEG_DEV"
	logCMD "ssh $RP ethtool -c $RP_PRIV_LEG_DEV"
	log "ethtool -g $RP_PRIV_LEG_DEV"
	logCMD "ssh $RP ethtool -g $RP_PRIV_LEG_DEV"
	log "ethtool -k $RP_PRIV_LEG_DEV"
	logCMD "ssh $RP ethtool -k $RP_PRIV_LEG_DEV"
	log "ethtool -i $RP_PRIV_LEG_DEV"
	logCMD "ssh $RP ethtool -i $RP_PRIV_LEG_DEV"
	log "ethtool -m $RP_PRIV_LEG_DEV"
	logCMD "ssh $RP ethtool -n $RP_PRIV_LEG_DEV"
	log "ethtool -T $RP_PRIV_LEG_DEV"
	logCMD "ssh $RP ethtool -T $RP_PRIV_LEG_DEV"
	log "ethtool -x $RP_PRIV_LEG_DEV"
	logCMD "ssh $RP ethtool -x $RP_PRIV_LEG_DEV"
	log "ethtool -P $RP_PRIV_LEG_DEV"
	logCMD "ssh $RP ethtool -P $RP_PRIV_LEG_DEV"
	log "ethtool -w $RP_PRIV_LEG_DEV"
	logCMD "ssh $RP ethtool -w $RP_PRIV_LEG_DEV"
	log "ethtool -l $RP_PRIV_LEG_DEV"
	logCMD "ssh $RP ethtool -l $RP_PRIV_LEG_DEV"
	log "ethtool --show-priv-flags $RP_PRIV_LEG_DEV"
	logCMD "ssh $RP ethtool --show-priv-flags $RP_PRIV_LEG_DEV"

	log "ethtool -a $RP_PUB_LEG_DEV"
	logCMD "ssh $RP ethtool -a $RP_PUB_LEG_DEV"
	log "ethtool -c $RP_PUB_LEG_DEV"
	logCMD "ssh $RP ethtool -c $RP_PUB_LEG_DEV"
	log "ethtool -g $RP_PUB_LEG_DEV"
	logCMD "ssh $RP ethtool -g $RP_PUB_LEG_DEV"
	log "ethtool -k $RP_PUB_LEG_DEV"
	logCMD "ssh $RP ethtool -k $RP_PUB_LEG_DEV"
	log "ethtool -i $RP_PUB_LEG_DEV"
	logCMD "ssh $RP ethtool -i $RP_PUB_LEG_DEV"
	log "ethtool -m $RP_PUB_LEG_DEV"
	logCMD "ssh $RP ethtool -n $RP_PUB_LEG_DEV"
	log "ethtool -T $RP_PUB_LEG_DEV"
	logCMD "ssh $RP ethtool -T $RP_PUB_LEG_DEV"
	log "ethtool -x $RP_PUB_LEG_DEV"
	logCMD "ssh $RP ethtool -x $RP_PUB_LEG_DEV"
	log "ethtool -P $RP_PUB_LEG_DEV"
	logCMD "ssh $RP ethtool -P $RP_PUB_LEG_DEV"
	log "ethtool -w $RP_PUB_LEG_DEV"
	logCMD "ssh $RP ethtool -w $RP_PUB_LEG_DEV"
	log "ethtool -l $RP_PUB_LEG_DEV"
	logCMD "ssh $RP ethtool -l $RP_PUB_LEG_DEV"
	log "ethtool --show-priv-flags $RP_PUB_LEG_DEV"
	logCMD "ssh $RP ethtool --show-priv-flags $RP_PUB_LEG_DEV"
	
}

cleanup() {
	#clean all potential datapaths
	#fwd
	wait
	set +e
	logCMD "ssh $LOADER ip route del $PUB_NET > /dev/null 2>&1"
	logCMD "ssh $INITIATOR ip route del $PRIV_NET > /dev/null 2>&1"
	#iptables
	log "Clean ip tables"
	logCMD "ssh $RP iptables -F"
	logCMD "ssh $RP iptables -t nat -F"
	#ovs
	log "Clean OVS flows"
	logCMD "ssh $RP ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br"

	ssh $LOADER pkill gonoodle
	ssh $INITIATOR pkill gonoodle

	pkill mpstat
	set -e
}

initTest() {
	#git pull?
	#init the RP depending on the datapath/cores/affinity etc
	#logCMD "ssh $RP sysctl -w net.ipv4.ip_forward=1"
	logCMD "ssh $LOADER ip route add $PUB_NET via $RP_PRIV_LEG_IP dev $LOADER_DEV"
	logCMD "ssh $INITIATOR ip route add $PRIV_NET via $RP_PUB_LEG_IP dev $INITIATOR_DEV"
	#add routing rules
}

collectCPULogs() {
	cpu=$1
	sleep_duration=$LOG_INTERVAL

	# Idle %age
	for (( dur=1; dur<=$LOG_DURATION; dur++ ))
	do
		output=`mpstat -P $cpu $sleep_duration 1| tail -1 | tr -s " " | cut -d " " -f10,12`
		idle=`echo $output | cut -d " " -f2`
		guest=`echo $output | cut -d " " -f1`
		echo $dur $idle >> $LOGDIR/${cpu}.idle
		echo $dur $guest >> $LOGDIR/${cpu}.guest
	done
}	

collectBWLogs() {
	sleep_duration=$LOG_INTERVAL

	BASE_RX_BYTES=`ssh $RP ethtool -S $RP_PRIV_LEG_DEV | grep "rx_bytes:" | awk '{print  $2}'`
	BASE_TX_BYTES=`ssh $RP ethtool -S $RP_PUB_LEG_DEV | grep "tx_bytes:" | awk '{print  $2}'`
	BASE_RX_DROPPED=`ssh $RP ethtool -S $RP_PRIV_LEG_DEV | grep "rx_out_buffer:" | awk '{print  $2}'`
	BASE_TX_DROPPED=`ssh $RP ethtool -S $RP_PUB_LEG_DEV | grep "tx_queue_dropped:" | awk '{print  $2}'`
	for (( dur=1; dur<=$LOG_DURATION; dur++ ))
	do
		sleep $sleep_duration
		# RX bytes
		rx_bytes=`ssh $RP ethtool -S $RP_PRIV_LEG_DEV | grep "rx_bytes:" | awk '{print  $2}'`
		echo $dur $((rx_bytes-BASE_RX_BYTES)) >> $LOGDIR/${RP_PRIV_LEG_DEV}.tput

		# TX bytes
		tx_bytes=`ssh $RP ethtool -S $RP_PUB_LEG_DEV | grep "tx_bytes:" | awk '{print  $2}'`
		echo $dur $((tx_bytes-BASE_TX_BYTES)) >> $LOGDIR/${RP_PUB_LEG_DEV}.tput

		# RX buffer overruns
		rx_dropped=`ssh $RP ethtool -S $RP_PRIV_LEG_DEV | grep "rx_out_buffer:" | awk '{print  $2}'`
		echo $dur $((rx_dropped-BASE_RX_DROPPED)) >> $LOGDIR/${RP_PRIV_LEG_DEV}.dropped

		# TX drops
		tx_dropped=`ssh $RP ethtool -S $RP_PUB_LEG_DEV | grep "rx_out_buffer:" | awk '{print  $2}'`
		echo $dur $((tx_dropped-BASE_TX_DROPPED)) >> $LOGDIR/${RP_PUB_LEG_DEV}.dropped

		BASE_RX_BYTES=$rx_bytes
		BASE_TX_BYTES=$tx_bytes
		BASE_RX_DROPPED=$rx_dropped
		BASE_TX_DROPPED=$tx_dropped
	done
}

plotLogs() {
	gnuplot -persist <<-EOFMarker
		set terminal dumb
		set multiplot layout 4,2 rowsfirst
		set yrange [0:$THROUGHPUT_YRANGE]

		plot "$LOGDIR/${RP_PRIV_LEG_DEV}.tput" using 1:2 with lines title "RX Bytes"
		#plot "$LOGDIR/${RP_PRIV_LEG_DEV}.dropped" using 1:2 with lines title "RX Dropped"

		plot "$LOGDIR/${RP_PUB_LEG_DEV}.tput" using 1:2 with lines title "TX Bytes"
		#plot "$LOGDIR/${RP_PUB_LEG_DEV}.dropped" using 1:2 with lines title "TX Dropped"

#		set yrange [0:$CPU_YRANGE]
#
#		set label 1 'Idle %' at graph .3,0.5
#		# User for instead of explicitly going over the list
#		plot "${LOGDIR}/0.idle" using 1:2 with lines title "CPU 0", \
#			"${LOGDIR}/1.idle" using 1:2 with lines title "CPU 1", \
#			"${LOGDIR}/2.idle" using 1:2 with lines title "CPU 2", \
#			"${LOGDIR}/3.idle" using 1:2 with lines title "CPU 3", \
#			"${LOGDIR}/4.idle" using 1:2 with lines title "CPU 4", \
#			"${LOGDIR}/5.idle" using 1:2 with lines title "CPU 5", \
#			"${LOGDIR}/6.idle" using 1:2 with lines title "CPU 6", \
#			"${LOGDIR}/7.idle" using 1:2 with lines title "CPU 7"
#
#		set label 1 'Guest %' at graph .3,0.5
#		# User for instead of explicitly going over the list
#		plot "${LOGDIR}/0.guest" using 1:2 with lines title "CPU 0", \
#			"${LOGDIR}/1.guest" using 1:2 with lines title "CPU 1", \
#			"${LOGDIR}/2.guest" using 1:2 with lines title "CPU 2", \
#			"${LOGDIR}/3.guest" using 1:2 with lines title "CPU 3", \
#			"${LOGDIR}/4.guest" using 1:2 with lines title "CPU 4", \
#			"${LOGDIR}/5.guest" using 1:2 with lines title "CPU 5", \
#			"${LOGDIR}/6.guest" using 1:2 with lines title "CPU 6", \
#			"${LOGDIR}/7.guest" using 1:2 with lines title "CPU 7"
	unset multiplot
	EOFMarker

}

runTest() {
	#start loader
	echo "staring loaded..."
	cmdBG "ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $INITIATOR_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${GS_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"
	sleep 1


	echo "staring initiator..."
	cmdBG "ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $LOADER_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"

}

runMetrics() {
	collectBWLogs &
	P2KILL+="$! "
	for ((cpus=0;cpus<NUM_CPUS;cpus++))
	do
		cpu=$((CPUSTART+cpus))
		collectCPULogs $cpu &
		P2KILL+="$! "

	done
}

host_vm_cpu_binding() {
	cpu_binding=$1
	if [ $cpu_binding = "dangling" ] ; then
		return
	fi
	for (( cpu=0; cpu<$NUM_CPUS; cpu++ )) 
	do
		bindcpu=$((CPU_START+cpu))
		virsh vcpupin $RPVM $dindcpu
	done
}

rp_irq_affinity() {
	affinity_mode=$1
	if [ $affinity_mode -eq 4 ] ; then
		ssh $RP C=-1 ; for r in `cat /proc/interrupts | grep $RP_PRIV_LEG_DEV | cut -f1 -d: ` ; do  C=$((C+1)) ; echo "obase=16;$((1<<$C))" | bc > /proc/irq/${r}/smp_affinity ; done
		ssh $RP C=3 ; for r in `cat /proc/interrupts | grep $RP_PUB_LEG_DEV | cut -f1 -d: ` ; do  C=$((C+1)) ; echo "obase=16;$((1<<$C))" | bc > /proc/irq/${r}/smp_affinity ; done
	else
		ssh $RP C=-1 ; for r in `cat /proc/interrupts | grep $RP_PRIV_LEG_DEV | cut -f1 -d: ` ; do  C=$((C+1)) ; echo "obase=16;$((1<<$C))" | bc > /proc/irq/${r}/smp_affinity ; done
		ssh $RP C=-1 ; for r in `cat /proc/interrupts | grep $RP_PUB_LEG_DEV | cut -f1 -d: ` ; do  C=$((C+1)) ; echo "obase=16;$((1<<$C))" | bc > /proc/irq/${r}/smp_affinity ; done
	fi

}

linux_forward_setup() {
	ssh $RP sysctl net.ipv4.ip_forward=1
}

linux_forward_nat_setup() {
	ssh $RP for i in {0..1000} ; do let dp=${GFN_PUB_PORT_START}+$i; let tdp=${GS_PORT_START}+$i ; iptables -t nat -A PREROUTING -i ens6 -p udp -m udp --dport $dp -j DNAT --to-destination ${LOADER_IP}:$tdp ; done
	ssh $RP iptables -t nat -A POSTROUTING -o ${RP_PUB_LEG_DEV} -j SNAT --to-source ${RP_PUB_LEG_IP}
	ssh $RP iptables -t nat -A POSTROUTING -o ${RP_PRIV_LEG_DEV} -j SNAT --to-source ${RP_PRIV_LEG_IP}
}

ovs_forward_setup() {
}

# linux_fwd linux_fwd_nat ovs_fwd ovs_fwd_nat ovs_fwd_ct
setup_tests() {
	tests=$1
	case $tests in 
		linux_fwd)
			linux_forward_setup()
			;;
		linux_fwd_nat)
			linux_forward_nat_setup()
			;;
		#ovs_fwd)
		#	ovs_forward_setup()
		#	;;
		#ovs_fwd_ct)
		#	ovs_forward_nat_setup()
		#	;;
	esac
}

killBGThreads() {
	#for p in $P2KILL ; do
	#	kill -9 $p
	#done
	echo "Waiting..."
	wait

}

### main ###
setup

echo "Clean Datapath"
cleanup

# Set profile
# Check for OFED?

echo "Init test"
initTest
echo "Run test"

set +e
shutdown_vm
set -e
for mode in $NIC_MODES
do
	log_before
	if [ $mode -eq "pt" ] ; then
		RPVM=rp
	else
		RPVM=rp_vf
	fi
	startup_vm
	RP=`virsh domifaddr $RPVM | grep ipv4 | awk '{print $4}'| cut -d"/" -f1`
	for profile in $TEST_PROFILE
	do
		startup_vm
		setup_vm
		ssh $RP mlnx_tune -p $profile
		for cpu_binding in $CPU_BINDINGS
		do
			host_vm_cpu_binding($cpu_binding)
			for  cpu_affinity in $CPU_AFFINITIES
			do
				rp_irq_affinity($cpu_affinity)
				do
					# echo "$profile, $cpu_binding, $cpu_affinity, $mode, $test"
					for t in $TESTS
					do
						setup_test $t
						run_Test
						runMetrics
						cleanup
						TEST_LOG_DIR="${mode}_${profile}_${cpu_binding}_${cpu_affinity}_${t}"
						mkdir -p /tmp/${TEST_LOG_DIR}
						mv $LOGDIR/* /tmp/${TEST_LOG_DIR}
						mv /tmp/${TEST_LOG_DIR} $LOGDIR
					done
				done
			done
		done
		shutdown_vm
	done
	log_after
	shutdown_vm
done


#log_before

plotLogs
