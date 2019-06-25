wait
#!/bin/bash

# TODO
# log() taking a param as a file
# Bandwidth stats in the RP instead of ssh
# script for setting up OVS NAT rules instead of sshing 
# suppress output from mlnx_tune and copy over the log file from rp
# OVS add rules scalabilty
# Check config for BM NIC_MODES
# Set channel in rp_irq_affinity before setting affinity
# For bonding add additional interfaces to the script
# Take the big loop outside as a separate script; this should run only a specific test


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
#	. BM

#RP Datapath
#------------
#1. Linux Forward
#2. Linux Forward with IPTables/NAT
#3. OVS Forward (with offload)
#4. OVS Forward with Statless NAT (with offload)
#5. OVS Forward without CT. (for now without offload)
#[3 - 5 : without offloads]

RESULTSDIR=${1:?result location not set}
# Test number for the test to run, from rp_test.list
TEST_TO_RUN=$2
TEST_TO_PLOT=$2
# read the config file
if test -f rp_test.config ; then
	. rp_test.config
else
	echo "Config file missing ... exiting"
fi
mkdir $LOGDIR

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

log "`date`  ##Start $RESULTSDIR##"
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
	#log "ethtool -w $RP_PRIV_LEG_DEV"
	#logCMD "ssh $RP ethtool -w $RP_PRIV_LEG_DEV"
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
	#log "ethtool -w $RP_PUB_LEG_DEV"
	#logCMD "ssh $RP ethtool -w $RP_PUB_LEG_DEV"
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
		echo $dur $idle >> $LOGDIR/${cpu}.idle
		echo $dur $util >> $LOGDIR/${cpu}.util
		echo $dur $guest >> $LOGDIR/${cpu}.guest
	done
}	

collectBWLogs() {

	ssh $RP bash $TOOLS/collect_ethtool_stats.bash $LOG_DURATION $LOG_INTERVAL $RP_PRIV_LEG_DEV $RP_PUB_LEG_DEV /tmp


	scp $RP:/tmp/${RP_PRIV_LEG_DEV}.tput $LOGDIR/${RP_PRIV_LEG_DEV}.tput
	scp $RP:/tmp/${RP_PUB_LEG_DEV}.tput $LOGDIR/${RP_PUB_LEG_DEV}.tput
	scp $RP:/tmp/${RP_PRIV_LEG_DEV}.dropped $LOGDIR/${RP_PRIV_LEG_DEV}.dropped
	scp $RP:/tmp/${RP_PUB_LEG_DEV}.dropped $LOGDIR/${RP_PUB_LEG_DEV}.dropped

}

plotLogs() {
	testdir=$1
	if [ -z GNUPLOT_TERMINAL ]
	then
		GNUPLOT_TERMINAL=qt
	fi
	gnuplot -persist <<-EOFMarker
		set terminal $GNUPLOT_TERMINAL
		set multiplot layout 4,2 rowsfirst
		set yrange [0:$THROUGHPUT_YRANGE]

		plot "$testdir/${RP_PRIV_LEG_DEV}.tput" using 1:2 with lines title "RX Bytes"
		plot "$testdir/${RP_PRIV_LEG_DEV}.dropped" using 1:2 with lines title "RX Dropped"

		plot "$testdir/${RP_PUB_LEG_DEV}.tput" using 1:2 with lines title "TX Bytes"
		plot "$testdir/${RP_PUB_LEG_DEV}.dropped" using 1:2 with lines title "TX Dropped"

		set yrange [0:$CPU_YRANGE]

		set label 1 'Idle %' at graph .3,0.5
		# User for instead of explicitly going over the list
		plot "${testdir}/0.util" using 1:2 with lines title "CPU 0", \
			"${testdir}/1.util" using 1:2 with lines title "CPU 1", \
			"${testdir}/2.util" using 1:2 with lines title "CPU 2", \
			"${testdir}/3.util" using 1:2 with lines title "CPU 3", \
			"${testdir}/4.util" using 1:2 with lines title "CPU 4", \
			"${testdir}/5.util" using 1:2 with lines title "CPU 5", \
			"${testdir}/6.util" using 1:2 with lines title "CPU 6", \
			"${testdir}/7.util" using 1:2 with lines title "CPU 7"

		set label 1 'Guest %' at graph .3,0.5
		# User for instead of explicitly going over the list
		plot "${testdir}/0.guest" using 1:2 with lines title "CPU 0", \
			"${testdir}/1.guest" using 1:2 with lines title "CPU 1", \
			"${testdir}/2.guest" using 1:2 with lines title "CPU 2", \
			"${testdir}/3.guest" using 1:2 with lines title "CPU 3", \
			"${testdir}/4.guest" using 1:2 with lines title "CPU 4", \
			"${testdir}/5.guest" using 1:2 with lines title "CPU 5", \
			"${testdir}/6.guest" using 1:2 with lines title "CPU 6", \
			"${testdir}/7.guest" using 1:2 with lines title "CPU 7"
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
		cpu=$((CPU_START+cpus))
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
		virsh vcpupin $RPVM $cpu $bindcpu  > /dev/null 2>&1
	done
	logCMD virsh vcpuinfo $RPVM
}

# XXX Fixme. The ssh below seems to have a couple of issues
rp_irq_affinity() {
	affinity_mode=$1
	# Set the # of channels
	ssh $RP ethtool -L $RP_PRIV_LEG_DEV combined $affinity_mode
	ssh $RP ethtool -L $RP_PUB_LEG_DEV combined $affinity_mode
	if [ $affinity_mode -eq 4 ] ; then
		ssh $RP "C=-1 ; for r in \`cat /proc/interrupts | grep ${RP_PRIV_LEG_DEV} | cut -f1 -d: \` ; do  C=\$((C+1)) ; echo \"obase=16;\$((1<<\$C))\" | bc > /proc/irq/\${r}/smp_affinity ; done"
		ssh $RP "C=3 ; for r in \`cat /proc/interrupts | grep ${RP_PUB_LEG_DEV} | cut -f1 -d: \` ; do  C=\$((C+1)) ; echo \"obase=16;\$((1<<\$C))\" | bc > /proc/irq/\${r}/smp_affinity ; done"
	else
		ssh $RP "C=-1 ; for r in \`cat /proc/interrupts | grep ${RP_PRIV_LEG_DEV} | cut -f1 -d: \` ; do  C=\$((C+1)) ; echo \"obase=16;\$((1<<\$C))\" | bc > /proc/irq/\${r}/smp_affinity ; done"
		ssh $RP "C=-1 ; for r in \`cat /proc/interrupts | grep ${RP_PUB_LEG_DEV} | cut -f1 -d: \` ; do  C=\$((C+1)) ; echo \"obase=16;\$((1<<\$C))\" | bc > /proc/irq/\${r}/smp_affinity ; done"
	fi
}

linux_forward_setup() {
	ssh $RP sysctl net.ipv4.ip_forward=1
	LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $INITIATOR_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${GFN_PUB_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
	INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $LOADER_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GS_PORT_START} -L :${GFN_PUB_PORT_START} -l 1000 -t $DURATION"
}

linux_forward_nat_setup() {
	nat_cmd="for i in {0..1000} ; do let dp=$GFN_PUB_PORT_START+\$i; let tdp=$GS_PORT_START+\$i ; iptables -t nat -A PREROUTING -i $RP_PUB_LEG_DEV -p udp -m udp --dport \$dp -j DNAT --to-destination ${LOADER_IP}:\$tdp ; done"
	ssh $RP $nat_cmd
	ssh $RP iptables -t nat -A POSTROUTING -o ${RP_PUB_LEG_DEV} -j SNAT --to-source ${RP_PUB_LEG_IP}
	ssh $RP iptables -t nat -A POSTROUTING -o ${RP_PRIV_LEG_DEV} -j SNAT --to-source ${RP_PRIV_LEG_IP}
	LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
	INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"
}

ovs_forward_setup() {
	# Add forwarding rules

	ssh $RP bash $TOOLS/set_ovs_cfg.bash ovs_forward_setup $BRPRIV $BRPUB $RP_PRIV_LEG_DEV $RP_PUB_LEG_DEV $RP_PRIV_PATCH_PORT $RP_PUB_PATCH_PORT $RP_PRIV_LEG_MAC $RP_PUB_LEG_MAC $LOADER_IP $INITIATOR_IP $LOADER_DEV_MAC $INITIATOR_DEV_MAC

	LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $INITIATOR_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${GFN_PUB_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
	INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $LOADER_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GS_PORT_START} -L :${GFN_PUB_PORT_START} -l 1000 -t $DURATION"
}

ovs_forward_nat_setup() {

	ssh $RP bash $TOOLS/set_ovs_cfg.bash ovs_forward_nat_setup $BRPRIV $BRPUB $RP_PRIV_LEG_DEV $RP_PUB_LEG_DEV $RP_PRIV_PATCH_PORT $RP_PUB_PATCH_PORT $RP_PRIV_LEG_MAC $RP_PUB_LEG_MAC $LOADER_IP $INITIATOR_IP $NUM_SESSIONS $GFN_PUB_PORT_START $GS_PORT_START $LOADER_DEV_MAC $INITIATOR_DEV_MAC $RP_PRIV_LEG_IP $RP_PUB_LEG_IP
	LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
	INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"

}

ovs_forward_ct_setup() {

	ssh $RP bash $TOOLS/set_ovs_cfg.bash ovs_forward_ct_setup $BRPRIV $BRPUB $RP_PRIV_LEG_DEV $RP_PUB_LEG_DEV $RP_PRIV_PATCH_PORT $RP_PUB_PATCH_PORT $RP_PRIV_LEG_MAC $RP_PUB_LEG_MAC $LOADER_IP $INITIATOR_IP $NUM_SESSIONS $GFN_PUB_PORT_START $GS_PORT_START $LOADER_DEV_MAC $INITIATOR_DEV_MAC $RP_PRIV_LEG_IP $RP_PUB_LEG_IP

	LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
	INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"

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
			setup_vm_ovs "no"
			ovs_forward_setup
			;;
		ovs_fwd_offload)
			setup_vm_ovs "yes"
			ovs_forward_setup
			;;
		ovs_fwd_nat)
			setup_vm_ovs "no"
			ovs_forward_nat_setup
			;;
		ovs_fwd_nat_offload)
			setup_vm_ovs "yes"
			ovs_forward_nat_setup
			;;
		ovs_fwd_ct)
			setup_vm_ovs "no"
			ovs_forward_ct_setup
			;;
		ovs_fwd_ct_offload)
			setup_vm_ovs "yes"
			ovs_forward_ct_setup
			;;
	esac
}

killBGThreads() {
	#for p in $P2KILL ; do
	#	kill -9 $p
	#done
	echo "Waiting..."
	wait

}

#if [ -n $TEST_TO_RUN ]
#then
#	echo "Test to run is $TEST_TO_RUN"
#fi

### main ###

if [ $DONT_RUN_TESTS != "yes" ]
then
	setup

	echo "Clean Datapath"
	cleanup

	# Set profile
	# Check for OFED?

	echo "Init test"
	initTest
fi

if [ $JUST_DISPLAY_TESTS = "yes" ]
then
	echo "# DO NOT hand edit. This is generated by $0 with the JUST_DISPLAY_TESTS "
	echo "# set in the config"
	echo 
fi

if [ $JUST_PLOT_RESULTS = "yes" -a -z $TEST_TO_PLOT ]
then
	echo "Need to specify Test # to plot"
	exit
fi

# XXX Add a loop for number of sessions : 500, 1000
# XXX Burst too.
# XXX H/A
disp_count=1 
done_run=false
for mode in $NIC_MODES
do
	if [ $DONT_RUN_TESTS != "yes" ]
	then
		if [ $mode = "pt" ] ; then
			RPVM=$RPVM_PT
		else
			RPVM=$RPVM_SRIOV
		fi
		shutdown_vm
	else
		echo 
		echo "# NiC mode : $mode"
		echo "------------------------------------------------------------------"
	fi
	for profile in $TEST_PROFILE
	do
		if [ $DONT_RUN_TESTS != "yes" ]
		then
			startup_vm
			log_before
			setup_vm
			ssh $RP mlnx_tune -p $profile > $LOGDIR/mlnx_tune.log 2>&1
		else
			echo
		fi
		for cpu_binding in $CPU_BINDINGS
		do
			if [ $DONT_RUN_TESTS != "yes" ]
			then
				host_vm_cpu_binding $cpu_binding
			fi
			for  cpu_affinity in $CPU_AFFINITIES
			do
				if [ $DONT_RUN_TESTS != "yes" ]
				then
					rp_irq_affinity $cpu_affinity
				fi
				# echo "$mode, $profile, $cpu_binding, $cpu_affinity, $test"
				for t in $TESTS
				do
					if [ $JUST_DISPLAY_TESTS = "yes" ]
					then
						echo "$disp_count: $mode, $profile, $cpu_binding, $cpu_affinity, $t"
					elif [ $JUST_PLOT_RESULTS = "yes" ]
					then
						if [ $TEST_TO_PLOT != $disp_count ]
						then
							disp_count=$((disp_count+1))
							continue
						fi
						TEST_LOG_DIR="${mode}_${profile}_${cpu_binding}_${cpu_affinity}_${t}"
						plotLogs $TEST_LOG_DIR
					else
						if [ -n $TEST_TO_RUN -a $TEST_TO_RUN != $disp_count ]
						then
							disp_count=$((disp_count+1))
							continue
						fi
						setup_tests $t
						echo "Running test $mode, $profile, $cpu_binding, $cpu_affinity, $t"
						runTest
						runMetrics
						# cleanup
						TEST_LOG_DIR="${mode}_${profile}_${cpu_binding}_${cpu_affinity}_${t}"
						mkdir -p /tmp/${TEST_LOG_DIR}
						mv $LOGDIR/* /tmp/${TEST_LOG_DIR}
						mv /tmp/${TEST_LOG_DIR} $LOGDIR
						if [ -n $TEST_TO_RUN ]
						then
							done_run="true"
							break
						fi
					fi
					disp_count=$((disp_count+1))
				done
				if [ $done_run = "true" ]
				then
					break
				fi
			done
			if [ $done_run = "true" ]
			then
				break
			fi
		done
		#if [ $DONT_RUN_TESTS != "yes" ]
		#then
		#	shutdown_vm
		#fi
		if [ $done_run = "true" ]
		then
			break
		fi
	done
	#if [ $DONT_RUN_TESTS != "yes" ]
	#then
	#	# log_after
	#	shutdown_vm
	#fi
	if [ $done_run = "true" ]
	then
		break
	fi
done
# Tar the log file
if [ "$(ls -A $LOGDIR)" ]
then
	tar -czf $LOGDIR.tar.gz $LOGDIR
fi
#log_before
