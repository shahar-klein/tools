wait
#!/bin/bash

# TODO
# log() taking a param as a file
# Bandwidth stats in the RP instead of ssh
# script for setting up OVS NAT rules instead of sshing 
# suppress output from mlnx_tune and copy over the log file from rp

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
PUB_NET="30.30.30.0/24"

GFN_PUB_PORT_START=8000
GS_PORT_START=10000

RP_PORT_START=5000

LOADER=10.0.0.147
LOADER_DEV=ens2
LOADER_IP=5.5.5.5

INITIATOR=10.0.0.148
INITIATOR_DEV=ens2
INITIATOR_IP=30.30.30.20

RPVM_PT=rp
RPVM_SROV=rp_vf

RPVM=$RPVM_PT
RP=192.168.122.5
RP_PRIV_LEG_IP=5.5.5.1
RP_PRIV_LEG_DEV=enp4s0

NUM_SESSIONS=5
BW_PER_SESSION=20m

RP_PUB_LEG_IP=30.30.30.100
RP_PUB_LEG_DEV=enp7s0

BRPUB=brpub
BRPRIV=brpriv
RP_PRIV_PATCH_PORT=priv-patch
RP_PUB_PATCH_PORT=pub-patch

TEST=${1:?test name not set}
TOOLS=/root/git/tools

# in seconds
DURATION=300
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
TESTS="ovs_fwd_nat"

#NIC_MODES="pt sriov"
NIC_MODES="pt"

#CPU_BINDINGS="dangling pinned"
CPU_BINDINGS="dangling"

#CPU_AFFINITIES="4 8"
CPU_AFFINITIES="4"

LOADER_CMD=
INITIATOR_CMD=
LOADER_DEV_MAC=
INITIATOR_DEV_MAC=
RP_PRIV_LEG_MAC=
RP_PUB_LEG_MAC=

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
	log "shutting down $RPVM"

	set +e
	virsh shutdown $RPVM
	set -e
	sleep 2
}

startup_vm() {
	VM=$RPVM
	VMIP=$RP

	log "starting $VM"

	set +e
	virsh start $VM
	set -e

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
	sleep 2
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

	# https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt:re arp
 	logCMD "ssh $RP sysctl net.ipv4.conf.all.arp_ignore=2"
 	logCMD "ssh $RP sysctl net.ipv4.conf.all.arp_announce=1"

	RP=`virsh domifaddr $RPVM | grep ipv4 | awk '{print $4}'| cut -d"/" -f1`

	RP_PRIV_LEG_MAC=`get_mac_dev $RP $RP_PRIV_LEG_DEV`
	flush_ip_dev $RP $RP_PRIV_LEG_DEV
	set_ip_dev $RP $RP_PRIV_LEG_DEV $RP_PRIV_LEG_IP
	
	RP_PUB_LEG_MAC=`get_mac_dev $RP $RP_PUB_LEG_DEV`
	flush_ip_dev $RP $RP_PUB_LEG_DEV
	set_ip_dev $RP $RP_PUB_LEG_DEV $RP_PUB_LEG_IP
	
	RP_PUB_LEG_MAC=`get_mac_dev $RP $RP_PUB_LEG_DEV`
	flush_ip_dev $RP $RP_PUB_LEG_DEV
	set_ip_dev $RP $RP_PUB_LEG_DEV $RP_PUB_LEG_IP

	logCMD "ssh $RP ethtool -X $RP_PRIV_LEG_DEV hfunc toeplitz"
	logCMD "ssh $RP ethtool -X $RP_PUB_LEG_DEV hfunc toeplitz"
}

setup_vm_ovs() {

	offload=$1
	logCMD "ssh $RP ovs-vsctl set open . other-config:hw-offload=false"
	if [ $offload = "yes" ]
	then
		logCMD "ssh $RP ovs-vsctl set open . other-config:hw-offload=true"
		logCMD "ssh $RP ethtool -K $RP_PRIV_LEG_DEV hw-tc-offload on"
		logCMD "ssh $RP ethtool -K $RP_PUB_LEG_DEV hw-tc-offload on"
	fi
	logCMD "ssh $RP systemctl restart openvswitch-switch.service"

	logCMD "ssh $RP ovs-vsctl add-br $BRPRIV"
	logCMD "ssh $RP ovs-ofctl del-flows $BRPRIV"
	logCMD "ssh $RP ovs-vsctl add-port $BRPRIV $RP_PRIV_LEG_DEV"

	logCMD "ssh $RP ovs-vsctl add-br $BRPUB"
	logCMD "ssh $RP ovs-ofctl del-flows $BRPUB"
	logCMD "ssh $RP ovs-vsctl add-port $BRPUB $RP_PUB_LEG_DEV"

	flush_ip_dev $RP $RP_PRIV_LEG_DEV
	flush_ip_dev $RP $RP_PUB_LEG_DEV

	set_ip_dev $RP $BRPRIV $RP_PRIV_LEG_IP
	set_ip_dev $RP $BRPUB $RP_PUB_LEG_IP

	logCMD "ssh $RP ip link set dev $RP_PRIV_LEG_DEV up"
	logCMD "ssh $RP ip link set dev $RP_PUB_LEG_DEV up"
	logCMD "ssh $RP ip link set dev $BRPRIV up"
	logCMD "ssh $RP ip link set dev $BRPUB up"

	# For VFs we need to update the bridge MAC addresses
	if [ $mode = "sriov" ]
	then
		RP_PRIV_LEG_MAC=`get_mac_dev $RP $RP_PRIV_LEG_DEV`
		RP_PUB_LEG_MAC=`get_mac_dev $RP $RP_PUB_LEG_DEV`

		logCMD "ssh $RP ovs-vsctl set bridge $BRPRIV other-config:hwaddr=\"$RP_PRIV_LEG_MAC\""
		logCMD "ssh $RP ovs-vsctl set bridge $BRPUB other-config:hwaddr=\"$RP_PUB_LEG_MAC\""

	fi

	# Create patch ports
	logCMD "ssh $RP ovs-vsctl add-port $BRPRIV $RP_PRIV_PATCH_PORT -- set interface $RP_PRIV_PATCH_PORT type=patch options:peer=$RP_PUB_PATCH_PORT"
	logCMD "ssh $RP ovs-vsctl add-port $BRPUB $RP_PUB_PATCH_PORT -- set interface $RP_PUB_PATCH_PORT type=patch options:peer=$RP_PRIV_PATCH_PORT"

	# Add ARP to the priv bridge
	logCMD "ssh $RP ovs-ofctl add-flow $BRPRIV priority=10,in_port=$RP_PRIV_LEG_DEV,arp,action=normal"
	logCMD "ssh $RP ovs-ofctl add-flow $BRPRIV priority=10,in_port=$BRPRIV,arp,action=normal"
	logCMD "ssh $RP ovs-ofctl add-flow $BRPRIV priority=50,in_port=$RP_PRIV_PATCH_PORT,arp,action=drop"
	logCMD "ssh $RP ovs-ofctl add-flow $BRPRIV priority=50,in_port=$RP_PRIV_PATCH_PORT,ip6,action=drop"
	logCMD "ssh $RP ovs-ofctl add-flow $BRPRIV priority=50,in_port=$RP_PRIV_PATCH_PORT,dl_dst=ff:ff:ff:ff:ff:ff,action=drop"
	
	
	# Add ARP to the pub bridge
	logCMD "ssh $RP ovs-ofctl add-flow $BRPUB priority=10,in_port=$RP_PUB_LEG_DEV,arp,action=normal"
	logCMD "ssh $RP ovs-ofctl add-flow $BRPUB priority=10,in_port=$BRPUB,arp,action=normal"
	logCMD "ssh $RP ovs-ofctl add-flow $BRPUB priority=50,in_port=$RP_PUB_PATCH_PORT,arp,action=drop"
	logCMD "ssh $RP ovs-ofctl add-flow $BRPUB priority=50,in_port=$RP_PUB_PATCH_PORT,ip6,action=drop"
	logCMD "ssh $RP ovs-ofctl add-flow $BRPUB priority=50,in_port=$RP_PUB_PATCH_PORT,dl_dst=ff:ff:ff:ff:ff:ff,action=drop"
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

# XXX Might want to keep the config around if we want to debug
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
		idle=`echo $output | cut -d " " -f2 | cut -d"." -f1`
		guest=`echo $output | cut -d " " -f1`
		util=$((100-idle))
		echo $dur $util >> $LOGDIR/${cpu}.util
		echo $dur $guest >> $LOGDIR/${cpu}.guest
	done
}	

collectBWLogs() {

	ssh $RP bash $TOOLS/collect_ethtool_stats.bash $DURATION $LOG_INTERVAL $RP_PRIV_LEG_DEV $RP_PUB_LEG_DEV /tmp


	scp $RP:/tmp/${RP_PRIV_LEG_DEV}.tput $LOGDIR/${RP_PRIV_LEG_DEV}.tput
	scp $RP:/tmp/${RP_PUB_LEG_DEV}.tput $LOGDIR/${RP_PUB_LEG_DEV}.tput
	scp $RP:/tmp/${RP_PRIV_LEG_DEV}.dropped $LOGDIR/${RP_PRIV_LEG_DEV}.dropped
	scp $RP:/tmp/${RP_PUB_LEG_DEV}.dropped $LOGDIR/${RP_PUB_LEG_DEV}.dropped

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
#		plot "${LOGDIR}/0.util" using 1:2 with lines title "CPU 0", \
#			"${LOGDIR}/1.util" using 1:2 with lines title "CPU 1", \
#			"${LOGDIR}/2.util" using 1:2 with lines title "CPU 2", \
#			"${LOGDIR}/3.util" using 1:2 with lines title "CPU 3", \
#			"${LOGDIR}/4.util" using 1:2 with lines title "CPU 4", \
#			"${LOGDIR}/5.util" using 1:2 with lines title "CPU 5", \
#			"${LOGDIR}/6.util" using 1:2 with lines title "CPU 6", \
#			"${LOGDIR}/7.util" using 1:2 with lines title "CPU 7"
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
	cmdBG $LOADER_CMD
	sleep 1


	echo "staring initiator..."
	cmdBG $INITIATOR_CMD

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
	echo "Waiting.."
	wait
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
	LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $INITIATOR_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${GFN_PUB_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
	INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $LOADER_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GS_PORT_START} -L :${GFN_PUB_PORT_START} -l 1000 -t $DURATION"
}

#GFN_PUB_PORT_START=8000
#GS_PORT_START=10000
#RP_PORT_START=5000

linux_forward_nat_setup() {
	nat_cmd="for i in {0..1000} ; do let dp=$GFN_PUB_PORT_START+\$i; let tdp=$GS_PORT_START+\$i ; iptables -t nat -A PREROUTING -i $RP_PUB_LEG_DEV -p udp -m udp --dport \$dp -j DNAT --to-destination ${LOADER_IP}:\$tdp ; done"
	ssh $RP $nat_cmd
	ssh $RP iptables -t nat -A POSTROUTING -o ${RP_PUB_LEG_DEV} -j SNAT --to-source ${RP_PUB_LEG_IP}
	ssh $RP iptables -t nat -A POSTROUTING -o ${RP_PRIV_LEG_DEV} -j SNAT --to-source ${RP_PRIV_LEG_IP}
	LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
	INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"
}

ovs_forward_setup() {
	setup_vm_ovs "no"

	# Add forwarding rules
	ssh $RP ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_LEG_DEV,udp,nw_dst=$LOADER_IP,action=$RP_PUB_PATCH_PORT
	ssh $RP ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,nw_dst=$LOADER_IP,action=mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,$RP_PRIV_LEG_DEV
	ssh $RP ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_LEG_DEV,udp,nw_dst=$INITIATOR_IP,action=$RP_PRIV_PATCH_PORT
	ssh $RP ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_PATCH_PORT,udp,nw_dst=$INITIATOR_IP,action=mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$INITIATOR_DEV_MAC,$RP_PUB_LEG_DEV
	LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $INITIATOR_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${GFN_PUB_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
	INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $LOADER_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GS_PORT_START} -L :${GFN_PUB_PORT_START} -l 1000 -t $DURATION"
}

ovs_forward_nat_setup() {
	setup_vm_ovs "no"
	echo "Done setting up OVS"

	# XXX It'll take a long time to add these flows via ssh!
	for ((i = 0; i < $NUM_SESSIONS; i++)); do
		GC_PORT=$((GFN_PUB_PORT_START+i))
		RP_PORT=$((RP_PORT_START+i))
		GS_PORT=$((GS_PORT_START+i))

		# Add the pub side of the flows
		ssh $RP ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_LEG_DEV,udp,nw_dst=$RP_PUB_LEG_IP,tp_dst=$RP_PORT,action=mod_nw_dst=$LOADER_IP,mod_tp_dst=$GS_PORT,$RP_PUB_PATCH_PORT
		ssh $RP ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_PATCH_PORT,udp,nw_dst=$LOADER_IP,tp_dst=$GS_PORT,action=mod_nw_src=$RP_PRIV_LEG_IP,mod_tp_src=$RP_PORT,mod_dl_src=$RP_PRIV_LEG_MAC,mod_dl_dst=$LOADER_DEV_MAC,$RP_PRIV_LEG_DEV

		# Add the priv _side of the flows
		ssh $RP ovs-ofctl add-flow $BRPRIV priority=100,in_port=$RP_PRIV_LEG_DEV,udp,nw_dst=$RP_PRIV_LEG_IP,tp_dst=$RP_PORT,action=mod_nw_dst=$INITIATOR_IP,mod_tp_dst=$GC_PORT,$RP_PRIV_PATCH_PORT
		ssh $RP ovs-ofctl add-flow $BRPUB priority=100,in_port=$RP_PUB_PATCH_PORT,udp,nw_dst=$INITIATOR_IP,tp_dst=$GC_PORT,action=mod_nw_src=$RP_PUB_LEG_IP,mod_tp_src=$RP_PORT,mod_dl_src=$RP_PUB_LEG_MAC,mod_dl_dst=$INITIATOR_DEV_MAC,$RP_PUB_LEG_DEV
	done

	LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
	INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${RP_PORT_START} -L :${GFN_PUB_PORT_START} -l 1000 -t $DURATION"

}



# linux_fwd linux_fwd_nat ovs_fwd ovs_fwd_nat ovs_fwd_ct
# XXX non-offload case
setup_tests() {
	tests=$1
	case $tests in 
		linux_fwd)
			linux_forward_setup
			;;
		linux_fwd_nat)
			linux_forward_nat_setup
			;;
		ovs_fwd)
			ovs_forward_setup
			;;
		ovs_fwd_nat)
			ovs_forward_nat_setup
			;;
		#ovs_fwd_ct)
		#	ovs_forward_ct_setup
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

# XXX Add a loop for number of sessions : 500, 1000
# XXX Burst too.
# XXX H/A
for mode in $NIC_MODES
do
	if [ $mode = "pt" ] ; then
		RPVM=rp
	else
		RPVM=rp_vf
	fi
	shutdown_vm
	for profile in $TEST_PROFILE
	do
		startup_vm
		log_before
		setup_vm
		ssh $RP mlnx_tune -p $profile > $LOGDIR/mlnx_tune.log
		for cpu_binding in $CPU_BINDINGS
		do
			host_vm_cpu_binding $cpu_binding
			for  cpu_affinity in $CPU_AFFINITIES
			do
				rp_irq_affinity $cpu_affinity
				# echo "$profile, $cpu_binding, $cpu_affinity, $mode, $test"
				for t in $TESTS
				do
					setup_tests $t
					echo "Run test"
					runTest
					runMetrics
					cleanup
					TEST_LOG_DIR="${mode}_${profile}_${cpu_binding}_${cpu_affinity}_${t}"
					mkdir -p /tmp/${TEST_LOG_DIR}
					mv $LOGDIR/* /tmp/${TEST_LOG_DIR}
					mv /tmp/${TEST_LOG_DIR} $LOGDIR
				done
			done
		done
		shutdown_vm
	done
	# log_after
	shutdown_vm
done

#log_before

plotLogs
