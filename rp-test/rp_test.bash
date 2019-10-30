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

# Location to store results from test run
LOGDIR=${1}
LOGDIR_HEAD=${LOGDIR}
# Test number for the test to run, from rp_test.list
case_num=$2
mode=$3
profile=$4
cpu_binding=$5
cpu_affinity=$6
dp_profile=$7
NUM_SESSIONS=$8
BW_PER_SESSION=$9
hfunc=${10}
MULTI_IP=no

#for logging

if [ $mode = pt_multip ] ; then
	mode=pt
	modeP=pt_multip
	MULTI_IP=yes
elif [ $mode = ct_multip ] ; then
	mode=ct
	modeP=ct_multip
	MULTI_IP=yes
else	
	modeP=$mode
fi


TEST_TO_RUN=$2
PLOT_DIR=$1
TEST_TO_PLOT=$2
# read the config file
if test -f rp_test.config ; then
	. rp_test.config
else
	echo "Config file missing ... exiting"
fi

if [ $RUN_TESTS = "yes" ]
then
	if [ -z $LOGDIR ]
	then
		echo "Need to specify location to save results"
		exit
	fi
	mkdir -p $LOGDIR
	LOG=${LOGDIR}/main.log
fi

if [ $PLOT_RESULTS = "yes" ]
then
	if [ -z $TEST_TO_PLOT -o -z $PLOT_DIR ]
	then
		echo "Need to specify Test # and its location to plot"
		exit
	fi
fi

# XXX Combine these three into one
if [ $RUN_TESTS = "yes" ]
then
	if [ $PLOT_RESULTS = "yes"  -o $DISPLAY_TESTS = "yes" ]
	then
		echo "Running tests, listing them and plotting are mutually exclusive"
		echo "1. $RUN_TESTS $PLOT_RESULTS $DISPLAY_TESTS"
		exit
	fi
fi

if [ $PLOT_RESULTS = "yes" ]
then
	if [ $RUN_TESTS = "yes"  -o $DISPLAY_TESTS = "yes" ]
	then
		echo "Running tests, listing them and plotting are mutually exclusive"
		echo "2. $RUN_TESTS $PLOT_RESULTS $DISPLAY_TESTS"
		exit
	fi
fi

if [ $DISPLAY_TESTS = "yes" ]
then
	if [ $PLOT_RESULTS = "yes"  -o $RUN_TESTS = "yes" ]
	then
		echo "Running tests, listing them and plotting are mutually exclusive"
		echo "3. $RUN_TESTS $PLOT_RESULTS $DISPLAY_TESTS"
		exit
	fi
fi

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

log "`date`  ##Start $LOGDIR##"
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
	mask=${4:-16}
	ssh $host ip a add dev $dev $ip/$mask
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

# XXX Consolidate these with the VM counterparts
shutdown_container() {
	VM=$1 
	log "shutting down $VM"

	set +e
	docker stop $VM >/dev/null 2>&1
	set -e
	sleep 2
}

wait_container() {
	VM=$1

	local chars=( \| / – \\ )
	local i=0
	while ! timeout 0.3 docker inspect --format '{{ .NetworkSettings.IPAddress }}'  $VM  &> /dev/null ; do
        	        if [ -t 1 ] ; then
                	        i=$((++i%4));
                        	echo "         (${chars[$i]})"
                        	echo -e "\033[2A"
                	fi
                	sleep 0.3

	done

	while [ 1 ] ; do
		VMIP=`docker inspect --format '{{ .NetworkSettings.IPAddress }}'  $VM`
		if [ -z $VMIP ] ; then
			echo "Waiting for $VM to get an ip address"
			sleep 2
			continue
		fi
		break
	done

	while ! timeout 0.3 ping -c 1 -n $VMIP  &> /dev/null ; do
        	        if [ -t 1 ] ; then
                	        i=$((++i%4));
                        	echo "         (${chars[$i]})"
                        	echo -e "\033[2A"
                	fi
                	sleep 0.3

	done
	RP=$VMIP
	sleep 2
}

startup_container() {
	log "starting $RPVM"
	VM=$1

	set +e
	#docker run -itd -v $HOME/container-ssh-keys/authorized_keys:/root/.ssh/authorized_keys --cap-add=NET_ADMIN --cpuset-cpus="0-7" --name $VM ${CONTAINER_IMAGE_ID} bin/bash
	docker start $VM
	set -e

	docker exec -it $VM service ssh restart >/dev/null 2>&1

	#XXX Start the service instead of this.
	# docker exec -it $VM /usr/share/openvswitch/scripts/ovs-ctl start > /dev/null2>&1 

	#docker network connect --ip $RP_PRIV_LEG_IP privleg $VM
	#docker network connect --ip $RP_PUB_LEG_IP publeg $VM
	
	echo "done startup_container"
	wait_container $VM
	echo "done wait_container"

	log "$VM ready"
}

reboot_container() {
	VM=$1

	log "rebooting $VM"

	docker restart $VM
	docker exec -it $VM   service ssh restart
	wait_container $VM
}

shutdown_vm() {
	VM=$1
	echo "shutting down $VM"
	log "shutting down $VM"

	set +e
	virsh shutdown $VM >/dev/null 2>&1
	set -e
	sleep 2
}
wait_vm() {
	VM=$1

	local chars=( \| / – \\ )
	local i=0
	while ! timeout 0.3 virsh domifaddr $VM  &> /dev/null ; do
        	        if [ -t 1 ] ; then
                	        i=$((++i%4));
                        	echo "         (${chars[$i]})"
                        	echo -e "\033[2A"
                	fi
                	sleep 0.3

	done

	while [ 1 ] ; do
		VMIP=`virsh domifaddr $VM | grep ipv4 | awk '{print $4}'| cut -d"/" -f1`
		if [ -z $VMIP ] ; then
			echo "Waiting for $VM to get an ip address"
			sleep 2
			continue
		fi
		break
	done

	while ! timeout 0.3 ping -c 1 -n $VMIP  &> /dev/null ; do
        	        if [ -t 1 ] ; then
                	        i=$((++i%4));
                        	echo "         (${chars[$i]})"
                        	echo -e "\033[2A"
                	fi
                	sleep 0.3

	done
	RP=$VMIP
	sleep 2
}


startup_vm() {
	VM=$1
	

	log "starting $VM"

	set +e
	virsh start $VM
	set -e
	
	wait_vm $VM

	log "$VM ready"
}

reboot_vm() {
	VM=$1

	log "rebooting $VM"

	virsh reboot $VM

	wait_vm $VM
}

setup() {
	#reboot_vm $RPVM $RP

	LOADER_DEV_MAC=`get_mac_dev $LOADER $LOADER_DEV`
	flush_ip_dev $LOADER $LOADER_DEV

	if [ $MULTI_IP = yes ] ; then
		set_ip_dev $LOADER $LOADER_DEV $LOADER_IP 16
		#ssh $LOADER "for t in 50 60 ; do for f in {0..250} ; do ip a add dev $LOADER_DEV 5.5.\$t.\$f ; done ; done"
		ssh $LOADER "s=\$(cat /root/git/tools/1000ips) ; for ip in \$s; do ip a add dev $LOADER_DEV \$ip ; done"
	else
		set_ip_dev $LOADER $LOADER_DEV $LOADER_IP
	fi 

	INITIATOR_DEV_MAC=`get_mac_dev $INITIATOR $INITIATOR_DEV`
	flush_ip_dev $INITIATOR $INITIATOR_DEV
	set_ip_dev $INITIATOR $INITIATOR_DEV $INITIATOR_IP
}

sethfunc() {
	hfunc=$1
	logCMD "ssh $RP ethtool -X $RP_PRIV_LEG_DEV hfunc $hfunc"
	ssh $RP ethtool -x $RP_PRIV_LEG_DEV | grep $hfunc | grep -q on
	if [ $? -ne 0 ] ; then
		echo "ERROR: $RP_PRIV_LEG_DEV hfunc is not $hfunc"
	fi
	logCMD "ssh $RP ethtool -X $RP_PUB_LEG_DEV hfunc $hfunc"
	ssh $RP ethtool -x $RP_PUB_LEG_DEV | grep $hfunc | grep -q on
	if [ $? -ne 0 ] ; then
		echo "ERROR: $RP_PUB_LEG_DEV hfunc is not $hfunc"
	fi
}

setup_vm() {

	local VM=$1

	# XXX We already have this info.
	#RP=`virsh domifaddr $VM | grep ipv4 | awk '{print $4}'| cut -d"/" -f1`

	# https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt:re arp
 	logCMD "ssh $RP sysctl net.ipv4.conf.all.arp_ignore=2"
 	logCMD "ssh $RP sysctl net.ipv4.conf.all.arp_announce=1"

	RP_PRIV_LEG_MAC=`get_mac_dev $RP $RP_PRIV_LEG_DEV`
	flush_ip_dev $RP $RP_PRIV_LEG_DEV
	set_ip_dev $RP $RP_PRIV_LEG_DEV $RP_PRIV_LEG_IP
	
	RP_PUB_LEG_MAC=`get_mac_dev $RP $RP_PUB_LEG_DEV`
	flush_ip_dev $RP $RP_PUB_LEG_DEV
	set_ip_dev $RP $RP_PUB_LEG_DEV $RP_PUB_LEG_IP

	logCMD "ssh $RP ethtool -K $RP_PRIV_LEG_DEV gro off"
	logCMD "ssh $RP ethtool -K $RP_PUB_LEG_DEV gro off"


	set +e
	# ssh $RP "cd $TOOLS ; git reset --hard ; git pull --force --no-edit" 2>&1 > /dev/null
	if [ $MULTI_IP = yes ] ; then
		logCMD "ssh $RP ip route add $PUB_NET via $RP_PUB_LEG_IP dev $RP_PUB_LEG_DEV 2>&1 > /dev/null"
		logCMD "ssh $RP ip route add $PRIV_NET via $RP_PRIV_LEG_IP dev $RP_PRIV_LEG_DEV 2>&1 > /dev/null"
	fi
	set -e
}

setup_vm_ovs() {

	nic_mode=$1
	offload=$2
	logCMD "ssh $RP ovs-vsctl set open . other-config:hw-offload=false"
	if [ $offload = "yes" ]
	then
		logCMD "ssh $RP ovs-vsctl set open . other-config:hw-offload=true"
		logCMD "ssh $RP ethtool -K $RP_PRIV_LEG_DEV hw-tc-offload on"
		logCMD "ssh $RP ethtool -K $RP_PUB_LEG_DEV hw-tc-offload on"
		if [ $nic_mode = "ha" ]; then
			logCMD "ssh $RP ethtool -K $RP_PRIV_LEG_DEV_HA hw-tc-offload on"
			logCMD "ssh $RP ethtool -K $RP_PUB_LEG_DEV_HA hw-tc-offload on"
		fi
	fi
	logCMD "ssh $RP systemctl restart openvswitch-switch.service"
	sleep 2
	logCMD "ssh $RP ovs-vsctl add-br $BRPRIV"
	logCMD "ssh $RP ovs-vsctl add-br $BRPUB"

	if [ $nic_mode = "ha" ]; then
		logCMD "ssh $RP ovs-vsctl add-bond $BRPRIV $RP_PRIV_LEG_HA_PORT $RP_PRIV_LEG_DEV_HA  $RP_PRIV_LEG_DEV bond_mode=active-backup"
		logCMD "ssh $RP ovs-vsctl add-bond $BRPUB $RP_PUB_LEG_HA_PORT $RP_PUB_LEG_DEV_HA  $RP_PUB_LEG_DEV bond_mode=active-backup"

		# Explicitly set the active interfaces
		logCMD "ssh $RP ovs-appctl bond/set-active-slave  $RP_PRIV_LEG_HA_PORT $RP_PRIV_LEG_DEV"
		logCMD "ssh $RP ovs-appctl bond/set-active-slave  $RP_PUB_LEG_HA_PORT $RP_PUB_LEG_DEV"
	else
		logCMD "ssh $RP ovs-vsctl add-port $BRPRIV $RP_PRIV_LEG_DEV"
		logCMD "ssh $RP ovs-vsctl add-port $BRPUB $RP_PUB_LEG_DEV"
	fi

	flush_ip_dev $RP $RP_PRIV_LEG_DEV
	flush_ip_dev $RP $RP_PUB_LEG_DEV

	set_ip_dev $RP $BRPRIV $RP_PRIV_LEG_IP
	set_ip_dev $RP $BRPUB $RP_PUB_LEG_IP

	logCMD "ssh $RP ip link set dev $RP_PRIV_LEG_DEV up"
	logCMD "ssh $RP ip link set dev $RP_PUB_LEG_DEV up"
	if [ $nic_mode = "ha" ]; then
		logCMD "ssh $RP ip link set dev $RP_PRIV_LEG_DEV_HA up"
		logCMD "ssh $RP ip link set dev $RP_PUB_LEG_DEV_HA up"
	fi
	logCMD "ssh $RP ip link set dev $BRPRIV up"
	logCMD "ssh $RP ip link set dev $BRPUB up"

	# For VFs we need to update the bridge MAC addresses
	if [ $nic_mode = "sriov" ]
	then
		RP_PRIV_LEG_MAC=`get_mac_dev $RP $RP_PRIV_LEG_DEV`
		RP_PUB_LEG_MAC=`get_mac_dev $RP $RP_PUB_LEG_DEV`

		logCMD "ssh $RP ovs-vsctl set bridge $BRPRIV other-config:hwaddr=\"$RP_PRIV_LEG_MAC\""
		logCMD "ssh $RP ovs-vsctl set bridge $BRPUB other-config:hwaddr=\"$RP_PUB_LEG_MAC\""

	fi

	# Create patch ports
	logCMD "ssh $RP ovs-vsctl add-port $BRPRIV $RP_PRIV_PATCH_PORT -- set interface $RP_PRIV_PATCH_PORT type=patch options:peer=$RP_PUB_PATCH_PORT"
	logCMD "ssh $RP ovs-vsctl add-port $BRPUB $RP_PUB_PATCH_PORT -- set interface $RP_PUB_PATCH_PORT type=patch options:peer=$RP_PRIV_PATCH_PORT"
}


log_run() {
	local VM=$1
	local test=$2
	local when=$3

	# We already have the IP.
	# local RP=`virsh domifaddr $VM | grep ipv4 | awk '{print $4}'| cut -d"/" -f1`

	log ""
	log "Test: $test: $when" 

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
	mode=$1
	#clean all potential datapaths
	#fwd
	wait
	set +e
	# logCMD "ssh $LOADER ip route del $PUB_NET > /dev/null 2>&1"
	# logCMD "ssh $INITIATOR ip route del $PRIV_NET > /dev/null 2>&1"

	ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br
	flush_ip_dev localhost $RP_PRIV_LEG_DEV_BM > /dev/null 2>&1
	flush_ip_dev localhost $RP_PUB_LEG_DEV_BM > /dev/null 2>&1

	#iptables
	log "Clean ip tables"
	logCMD "ssh $RP iptables -F"
	logCMD "ssh $RP iptables -t nat -F"

	#ovs
	log "Clean OVS flows"
	logCMD "ssh $RP ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br"

	logCMD "ssh $RP tc filter del dev $RP_PRIV_LEG_DEV parent ffff: > /dev/null 2>&1"
	logCMD "ssh $RP tc filter del dev $RP_PUB_LEG_DEV parent ffff: > /dev/null 2>&1"
	# echo "cleaned up OVS"
	# ssh $RP ovs-vsctl show

	# XXX Set the IPs back, if needed (this is needed after OVS cleanup only)
	flush_ip_dev $RP $RP_PRIV_LEG_DEV
	set_ip_dev $RP $RP_PRIV_LEG_DEV $RP_PRIV_LEG_IP

	flush_ip_dev $RP $RP_PUB_LEG_DEV
	set_ip_dev $RP $RP_PUB_LEG_DEV $RP_PUB_LEG_IP

	ssh $LOADER pkill -9 gonoodle
	ssh $INITIATOR pkill -9 gonoodle

	ssh $LOADER "ps -ef | grep collect_loader_ethtool_stats | awk '{print \$2}' | xargs kill -9 2>&1 > /dev/null" 2>&1 > /dev/null

	set -e
}

initTest() {
	#git pull?
	#init the RP depending on the datapath/cores/affinity etc
	#logCMD "ssh $RP sysctl -w net.ipv4.ip_forward=1"
	logCMD "ssh $LOADER ip route add $PUB_NET via $RP_PRIV_LEG_IP dev $LOADER_DEV 2>&1 >/dev/null"
	logCMD "ssh $INITIATOR ip route add $PRIV_NET via $RP_PUB_LEG_IP dev $INITIATOR_DEV 2>&1 >/dev/null"
	#add routing rules
}

collectCPULogs() {
	cpu=$1
	sleep_duration=$LOG_INTERVAL

	# Idle %age
	for (( dur=1; dur<=$LOG_DURATION; dur++ ))
	do
		output=`mpstat -P $cpu $sleep_duration 1| tail -1 | tr -s " " | cut -d " " -f5,10,12`
		#sys=`echo $output | cut -d " " -f1 | cut -d"." -f1`
		#guest=`echo $output | cut -d " " -f2 | cut -d"." -f1` 
		#idle=`echo $output | cut -d " " -f3 | cut -d"." -f1`
		#util=$((100-idle))
		#echo $sys, $guest, $idle, $util
		#echo $dur $idle >> $LOGDIR/${cpu}.idle
		#echo $dur $sys >> $LOGDIR/${cpu}.sys
		#echo $dur $util >> $LOGDIR/${cpu}.util
		#echo $dur $guest >> $LOGDIR/${cpu}.guest
		echo $output >> $LOGDIR/${cpu}.info
	done
	#cat $LOGDIR/${cpu}.info | while read s g i
	#do
	#	echo $s $g $i
	#done
}

collectLoaderBWLogs() {
	
	ssh $LOADER bash $TOOLS/collect_loader_ethtool_stats.bash $LOG_DURATION $LOG_INTERVAL $LOADER_DEV /tmp

	scp $LOADER:/tmp/${LOADER_DEV}.tput $LOGDIR/${LOADER_DEV}_TX.tput > /dev/null 2>&1
}

collectBWLogs() {
	nic_mode=$1

	ssh $RP bash $TOOLS/collect_ethtool_stats.bash $LOG_DURATION $LOG_INTERVAL $RP_PRIV_LEG_DEV $RP_PUB_LEG_DEV $RP_PRIV_LEG_DEV_HA $RP_PUB_LEG_DEV_HA /tmp $nic_mode

 
	scp $RP:/tmp/${RP_PRIV_LEG_DEV}.tput $LOGDIR/${RP_PRIV_LEG_DEV}.tput > /dev/null 2>&1
	scp $RP:/tmp/${RP_PUB_LEG_DEV}.tput $LOGDIR/${RP_PUB_LEG_DEV}.tput > /dev/null 2>&1
	scp $RP:/tmp/${RP_PRIV_LEG_DEV}.dropped $LOGDIR/${RP_PRIV_LEG_DEV}.dropped > /dev/null 2>&1
	scp $RP:/tmp/${RP_PUB_LEG_DEV}.dropped $LOGDIR/${RP_PUB_LEG_DEV}.dropped > /dev/null 2>&1
	scp $RP:/tmp/${RP_PRIV_LEG_DEV_HA}.tput $LOGDIR/${RP_PRIV_LEG_DEV_HA}.tput > /dev/null 2>&1
	scp $RP:/tmp/${RP_PUB_LEG_DEV_HA}.tput $LOGDIR/${RP_PUB_LEG_DEV_HA}.tput > /dev/null 2>&1
	scp $RP:/tmp/${RP_PRIV_LEG_DEV_HA}.dropped $LOGDIR/${RP_PRIV_LEG_DEV_HA}.dropped > /dev/null 2>&1
	scp $RP:/tmp/${RP_PUB_LEG_DEV_HA}.dropped $LOGDIR/${RP_PUB_LEG_DEV_HA}.dropped > /dev/null 2>&1

}

plotLogs() {
	dir=$1
	test=$2
	testdir=$1/$2
	test2plot=$3
	#if [ -z GNUPLOT_TERMINAL ]
	#then
	#	GNUPLOT_TERMINAL=qt
	#fi
	gnuplot -persist <<-EOFMarker
	
		set multiplot layout 1,2 rowsfirst title "Test #$test2plot - Bandwidth in Bytes/sec"

		# Range assuming max os 15Gbps
		set yrange [*:1500000000]
		set label 1 'Bytes/sec' at graph .3,.1
		plot "$testdir/${RP_PRIV_LEG_DEV}.tput" using 1:2 with lines title "RX Bytes", \
			"$testdir/${RP_PUB_LEG_DEV}.tput" using 1:2 with lines title "TX Bytes"

		# These are packets, so use 1000000 as the upper limit, as an estimate.
		set yrange [0:1000000]
		set label 1 'Packets/sec' at graph .3,.1
		plot "$testdir/${RP_PRIV_LEG_DEV}.dropped" using 1:2 with lines title "RX Packets Dropped", \
			"$testdir/${RP_PUB_LEG_DEV}.dropped" using 1:2 with lines title "TX Packets Dropped"


		unset multiplot
	EOFMarker

	gnuplot -persist <<-EOFMarker
		set multiplot layout 4,2 rowsfirst title "Test #$test2plot - CPU Utilization"
		set yrange [0:100]
		plot "${testdir}/1.util" using 1:2 with lines title "CPU 1"
		plot "${testdir}/2.util" using 1:2 with lines title "CPU 2"
		plot "${testdir}/3.util" using 1:2 with lines title "CPU 3"
		plot "${testdir}/4.util" using 1:2 with lines title "CPU 4"

		# Use for instead of explicitly going over the list
		set yrange [0:100]
		plot "${testdir}/5.util" using 1:2 with lines title "CPU 5"
		plot "${testdir}/6.util" using 1:2 with lines title "CPU 6"
		plot "${testdir}/7.util" using 1:2 with lines title "CPU 7"
		plot "${testdir}/8.util" using 1:2 with lines title "CPU 8"
		unset multiplot
	EOFMarker

	# Plot the guest CPU info from the host
#	gnuplot -persist <<-EOFMarker
#		set multiplot layout 1,2 rowsfirst title "Test #$test2plot"
#		set label 1 'Host % utilization' at graph .3,0.2
#		set yrange [0:100]
#		# Use for instead of explicitly going over the list
#		plot "${testdir}/1.util" using 1:2 with lines title "CPU 1", \
#			"${testdir}/2.util" using 1:2 with lines title "CPU 2", \
#			"${testdir}/3.util" using 1:2 with lines title "CPU 3", \
#			"${testdir}/4.util" using 1:2 with lines title "CPU 4", \
#			"${testdir}/5.util" using 1:2 with lines title "CPU 5", \
#			"${testdir}/6.util" using 1:2 with lines title "CPU 6", \
#			"${testdir}/7.util" using 1:2 with lines title "CPU 7", \
#			"${testdir}/8.util" using 1:2 with lines title "CPU 8"
#
#
#		set label 1 'Guest % utilization' at graph .3,0.2
#		# Use for instead of explicitly going over the list
#		set yrange [0:100]
#		plot "${testdir}/1.guest" using 1:2 with lines title "CPU 1", \
#			"${testdir}/2.guest" using 1:2 with lines title "CPU 2", \
#			"${testdir}/3.guest" using 1:2 with lines title "CPU 3", \
#			"${testdir}/4.guest" using 1:2 with lines title "CPU 4", \
#			"${testdir}/5.guest" using 1:2 with lines title "CPU 5", \
#			"${testdir}/6.guest" using 1:2 with lines title "CPU 6", \
#			"${testdir}/7.guest" using 1:2 with lines title "CPU 7", \
#			"${testdir}/8.guest" using 1:2 with lines title "CPU 8"
#		unset multiplot
#	EOFMarker

}

runTest() {
	#start loader
	#echo "staring loaded..."
	cmdBG $LOADER_CMD
	sleep 5


	#echo "staring initiator..."
	cmdBG $INITIATOR_CMD

}

runMetrics() {
	nic_mode=$1
	collectBWLogs $nic_mode &
	P2KILL+="$! "
	collectLoaderBWLogs &
	P2KILL+="$! "
	for ((cpu=0;cpu<$TOTAL_CPUS;cpu++))
	do
		collectCPULogs $cpu &
		P2KILL+="$! "

	done
	#echo "Waiting.."
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
	PRIV_ITF=$2
	PUB_ITF=$3

	set +e
	ssh $RP systemctl status irqbalance > /dev/null 2>&1
	set -e

	# Set the # of channels
	ssh $RP ethtool -L $PRIV_ITF combined $affinity_mode > /dev/null 2>&1
	ssh $RP ethtool -L $PUB_ITF combined $affinity_mode > /dev/null 2>&1
	if [ $affinity_mode -eq 4 ] ; then
		ssh $RP "C=-1 ; for r in \`cat /proc/interrupts | grep ${PRIV_ITF} | cut -f1 -d: \` ; do  C=\$((C+1)) ; echo \"obase=16;\$((1<<\$C))\" | bc > /proc/irq/\${r}/smp_affinity ; done"
		ssh $RP "C=3 ; for r in \`cat /proc/interrupts | grep ${PUB_ITF} | cut -f1 -d: \` ; do  C=\$((C+1)) ; echo \"obase=16;\$((1<<\$C))\" | bc > /proc/irq/\${r}/smp_affinity ; done"
	else
		ssh $RP "C=-1 ; for r in \`cat /proc/interrupts | grep ${PRIV_ITF} | cut -f1 -d: \` ; do  C=\$((C+1)) ; echo \"obase=16;\$((1<<\$C))\" | bc > /proc/irq/\${r}/smp_affinity ; done"
		ssh $RP "C=-1 ; for r in \`cat /proc/interrupts | grep ${PUB_ITF} | cut -f1 -d: \` ; do  C=\$((C+1)) ; echo \"obase=16;\$((1<<\$C))\" | bc > /proc/irq/\${r}/smp_affinity ; done"
	fi
}

setup_buffer_size() {
	buffer_size=$1
	set +e
	logCMD "ssh $RP ethtool -G $RP_PRIV_LEG_DEV rx $buffer_size"
	logCMD "ssh $RP ethtool -G $RP_PUB_LEG_DEV tx $buffer_size"
	set -e
}

linux_forward_setup() {
	ssh $RP sysctl net.ipv4.ip_forward=1 >/dev/null 2>&1
	LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $INITIATOR_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${GFN_PUB_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
	INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $LOADER_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GS_PORT_START} -L :${GFN_PUB_PORT_START} -l 1000 -t $DURATION"
}

linux_forward_nat_setup() {
	ssh $RP sysctl net.ipv4.ip_forward=1 >/dev/null 2>&1

	if [ $MULTI_IP = no ] ; then
		nat_cmd="for i in {0..1000} ; do let dp=$GFN_PUB_PORT_START+\$i; let tdp=$GS_PORT_START+\$i ; iptables -t nat -A PREROUTING -i $RP_PUB_LEG_DEV -p udp -m udp --dport \$dp -j DNAT --to-destination ${LOADER_IP}:\$tdp ; done"
		ssh $RP $nat_cmd
	else
		#VIDEO 0-1000
		nat_cmd="i=0 ; s=\$(cat /root/git/tools/1000ips) ; for ip in \$s; do let dp=$GFN_PUB_PORT_START+\$i ; iptables -t nat -A PREROUTING -i $RP_PUB_LEG_DEV -p udp -m udp --dport \$dp -m comment --comment VIDEO -j DNAT --to-destination \$ip:47998 ; i=\$((i + 1)) ; done"
		#nat_cmd="i=0 ; for ip in `cat $RAND_IPS` ; do let dp=$GFN_PUB_PORT_START+\$i ; iptables -t nat -A PREROUTING -i $RP_PUB_LEG_DEV -p udp -m udp --dport \$dp -m comment --comment VIDEO -j DNAT --to-destination \$ip:47998 ; i=$((i + 1)) ; done"
		ssh $RP $nat_cmd
		#AUDIO 1000-2000
		#nat_cmd="for i in {0..250} ; do let dp=$GFN_PUB_PORT_START+1000+\$i ; iptables -t nat -A PREROUTING -i $RP_PUB_LEG_DEV -p udp -m udp --dport \$dp -m comment --comment AUDIO -j DNAT --to-destination 5.5.50.\$i:48000 ; done"
		#ssh $RP $nat_cmd
	fi

	ssh $RP iptables -t nat -A POSTROUTING -o ${RP_PUB_LEG_DEV} -j SNAT --to-source ${RP_PUB_LEG_IP}
	ssh $RP iptables -t nat -A POSTROUTING -o ${RP_PRIV_LEG_DEV} -j SNAT --to-source ${RP_PRIV_LEG_IP}

	if [ $MULTI_IP = no ] ; then
		#With Burst
		#LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION -r 60:140"
		LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
		INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"
	else
		
		LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader_multi -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L 5.5.50.0:47998 -l 1000 -t $DURATION"
		INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"
	fi
}

ovs_forward_setup() {
	# Add forwarding rules

	ssh $RP bash $TOOLS/set_ovs_cfg.bash ovs_forward_setup $BRPRIV $BRPUB $RP_PRIV_LEG_DEV $RP_PUB_LEG_DEV $RP_PRIV_PATCH_PORT $RP_PUB_PATCH_PORT $RP_PRIV_LEG_MAC $RP_PUB_LEG_MAC $LOADER_IP $INITIATOR_IP $LOADER_DEV_MAC $INITIATOR_DEV_MAC

	LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $INITIATOR_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${GFN_PUB_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
	INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $LOADER_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GS_PORT_START} -L :${GFN_PUB_PORT_START} -l 1000 -t $DURATION"
}

ovs_forward_nat_setup() {

	ssh $RP bash $TOOLS/set_ovs_cfg.bash ovs_forward_nat_setup $MULTI_IP $BRPRIV $BRPUB $RP_PRIV_LEG_DEV $RP_PUB_LEG_DEV $RP_PRIV_PATCH_PORT $RP_PUB_PATCH_PORT $RP_PRIV_LEG_MAC $RP_PUB_LEG_MAC $LOADER_IP $INITIATOR_IP $NUM_SESSIONS $GFN_PUB_PORT_START $GS_PORT_START $LOADER_DEV_MAC $INITIATOR_DEV_MAC $RP_PRIV_LEG_IP $RP_PUB_LEG_IP
	#LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
	#INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"
	if [ $MULTI_IP = no ] ; then
		LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
		INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"
	else
		LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader_multi -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L 5.5.50.0:47998 -l 1000 -t $DURATION"
		INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"
	fi

}

tc_forward_ct_setup() {
	offload=$1

	if [ $offload = "yes" ]; then
		logCMD "ssh $RP ethtool -K $RP_PRIV_LEG_DEV hw-tc-offload on"
		logCMD "ssh $RP ethtool -K $RP_PUB_LEG_DEV hw-tc-offload on"
	fi

	# Remove need for $BRPRIV $BRPUB $RP_PRIV_PATCH_PORT $RP_PUB_PATCH_POR
	set -x
	ssh $RP bash $TOOLS/set_ovs_cfg.bash tc_ct_setup $MULTI_IP $BRPRIV $BRPUB $RP_PRIV_LEG_DEV $RP_PUB_LEG_DEV $RP_PRIV_PATCH_PORT $RP_PUB_PATCH_PORT $RP_PRIV_LEG_MAC $RP_PUB_LEG_MAC $LOADER_IP $INITIATOR_IP $NUM_SESSIONS $GFN_PUB_PORT_START $GS_PORT_START $LOADER_DEV_MAC $INITIATOR_DEV_MAC $RP_PRIV_LEG_IP $RP_PUB_LEG_IP
	set +x

	if [ $MULTI_IP = no ] ; then
		LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS  -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
		INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS  -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"
	else
		LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader_multi -C $NUM_SESSIONS -R  $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L 5.5.50.0:47998 -l 1000 -t $DURATION"
		INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R  100 -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"
	fi

}

ovs_forward_ct_setup() {

	ssh $RP bash $TOOLS/set_ovs_cfg.bash ovs_forward_ct_setup $MULTI_IP $BRPRIV $BRPUB $RP_PRIV_LEG_DEV $RP_PUB_LEG_DEV $RP_PRIV_PATCH_PORT $RP_PUB_PATCH_PORT $RP_PRIV_LEG_MAC $RP_PUB_LEG_MAC $LOADER_IP $INITIATOR_IP $NUM_SESSIONS $GFN_PUB_PORT_START $GS_PORT_START $LOADER_DEV_MAC $INITIATOR_DEV_MAC $RP_PRIV_LEG_IP $RP_PUB_LEG_IP

	#LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
	#INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"
	if [ $MULTI_IP = no ] ; then
		LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader -C $NUM_SESSIONS -R $NUM_SESSIONS  -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L :${GS_PORT_START} -l 1000 -t $DURATION"
		INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R $NUM_SESSIONS  -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"
	else
		
		LOADER_CMD="ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $RP_PRIV_LEG_IP --rp loader_multi -C $NUM_SESSIONS -R  $NUM_SESSIONS -M 10 -b $BW_PER_SESSION -p ${RP_PORT_START} -L 5.5.50.0:47998 -l 1000 -t $DURATION"
		INITIATOR_CMD="ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $RP_PUB_LEG_IP --rp initiator -C $NUM_SESSIONS -R  100 -M 1 -b 1k -p ${GFN_PUB_PORT_START} -L :${RP_PORT_START} -l 1000 -t $DURATION"
	fi

}


# linux_fwd linux_fwd_nat ovs_fwd ovs_fwd_nat ovs_fwd_ct
# XXX non-offload case
setup_dp_profile() {
	nic_mode=$1
	dp=$2
	case $dp in 
		linux_fwd)
			linux_forward_setup
			;;
		linux_fwd_nat)
			linux_forward_nat_setup
			;;
		tc_fwd_ct)
			tc_forward_ct_setup "no"
			;;
		tc_fwd_ct_offload)
			tc_forward_ct_setup "yes"
			;;
		ovs_fwd)
			setup_vm_ovs $nic_mode "no"
			ovs_forward_setup
			;;
		ovs_fwd_offload)
			setup_vm_ovs $nic_mode "yes"
			ovs_forward_setup
			;;
		ovs_fwd_nat)
			setup_vm_ovs $nic_mode "no"
			ovs_forward_nat_setup
			;;
		ovs_fwd_nat_offload)
			setup_vm_ovs $nic_mode "yes"
			ovs_forward_nat_setup
			;;
		ovs_fwd_ct)
			setup_vm_ovs $nic_mode "no"
			ovs_forward_ct_setup
			;;
		ovs_fwd_ct_offload)
			setup_vm_ovs $nic_mode "yes"
			ovs_forward_ct_setup
			;;
	esac
}

killBGThreads() {
	#for p in $P2KILL ; do
	#	kill -9 $p
	#done
	#echo "Waiting..."
	wait

}

#if [ -n "$TEST_TO_RUN" ]
#then
#	echo "Test to run is $TEST_TO_RUN"
#fi

### main ###

if [ $RUN_TESTS = "yes" ]
then
	#set up the test env according to the input:
	LOGDIR=${LOGDIR_HEAD}/${modeP}_${profile}_${cpu_binding}_${cpu_affinity}_${dp_profile}_${hfunc}_${NUM_SESSIONS}
	mkdir -v -p $LOGDIR > /dev/null 2>&1

	setup

	#echo "Initializing test .."
	#cleanup

	shutdown_vm $RPVM_PT
	shutdown_vm $RPVM_CT
	shutdown_vm $RPVM_SRIOV
	shutdown_vm $RPVM_HA
	# shutdown_container $RPVM_CONTAINER

	# Set profile
	# Check for OFED?

	initTest
fi

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

if [ $mode = "pt" ] ; then
	RPVM=$RPVM_PT
	RP_PRIV_LEG_DEV=$RP_PRIV_LEG_DEV_VM
	RP_PUB_LEG_DEV=$RP_PUB_LEG_DEV_VM
elif [ $mode = "ct" ] ; then
	RPVM=$RPVM_CT
	RP_PRIV_LEG_DEV=$RP_PRIV_LEG_DEV_VM
	RP_PUB_LEG_DEV=$RP_PUB_LEG_DEV_VM
elif [ $mode = "sriov" ] ; then
	RPVM=$RPVM_SRIOV
	RP_PRIV_LEG_DEV=$RP_PRIV_LEG_DEV_VM
	RP_PUB_LEG_DEV=$RP_PUB_LEG_DEV_VM
elif [ $mode = "ha" ] ; then
	RPVM=$RPVM_HA
	RP_PRIV_LEG_DEV=$RP_PRIV_LEG_DEV_VM
	RP_PUB_LEG_DEV=$RP_PUB_LEG_DEV_VM
elif [ $mode = "bm" ] ; then
	RP=$RP_BM
	RPVM=$RPVM_CONTAINER
	RP_PRIV_LEG_DEV=$RP_PRIV_LEG_DEV_BM
	RP_PUB_LEG_DEV=$RP_PUB_LEG_DEV_BM
else
	echo "unknown mode $mode, quitting.. "
	exit
fi
if [ $mode != "bm" ] ; then
	startup_vm $RPVM
fi
cleanup $mode
if [ $RPVM != $RPVM_CONTAINER ]; then
	log ""
	log "Dominfo $VM "
	log "========================================="
	logCMD "virsh dominfo $VM"
#else
#	log ""
#	log "Container $VM "
#	log "========================================="
#	logCMD "docker inspect $VM"
fi
log_run $RPVM ${mode}_${profile}_${cpu_binding}_${cpu_affinity}_${dp_profile}_${NUM_SESSIONS}_${BW_PER_SESSION} "Before"
setup_vm $RPVM

# XXX mlnx_tune has some issues with 
# "AttributeError: 'NoneType' object has no attribute 'report_status'"
# when run in the SRIOV VM.
#if [ $profile != "NONE" -a $mode != "sriov" ] ; then
#	ssh $RP mlnx_tune -p $profile > $LOGDIR/mlnx_tune.log 2>&1
#fi

# it is 1024 by default
if [ $profile -ne 1024 ]; then
	setup_buffer_size $profile
fi

#XXX not clear about pinning on the host
if [ $mode != "bm" ]; then
	host_vm_cpu_binding $cpu_binding
fi
rp_irq_affinity $cpu_affinity $RP_PRIV_LEG_DEV $RP_PUB_LEG_DEV
if [ $mode = "ha" ]; then
	ssh $RP ip link set dev $RP_PRIV_LEG_DEV_HA up
	ssh $RP ip link set dev $RP_PUB_LEG_DEV_HA up
	#set -x
	rp_irq_affinity $cpu_affinity $RP_PRIV_LEG_DEV_HA $RP_PUB_LEG_DEV_HA
	#set +x
fi

setup_dp_profile $mode $dp_profile
sethfunc $hfunc
echo "Running: $modeP, $profile, $cpu_binding CPU, $cpu_affinity, $dp_profile, hfunc $hfunc, $NUM_SESSIONS sessions at $BW_PER_SESSION bps"
runTest
runMetrics $mode
#echo "Tar'ing $LOGDIR_HEAD as $LOGDIR_HEAD.tar.gz"
#tar -czf $LOGDIR_HEAD.tar.gz $LOGDIR_HEAD > /dev/null 2>&1
#cleanup

log_run $RPVM ${mode}_${profile}_${cpu_binding}_${cpu_affinity}_${dp_profile}_${NUM_SESSIONS}_${BW_PER_SESSION} "After"
exit

if [ $DISPLAY_TESTS = "yes" ]
then
	echo "# DO NOT hand edit. This is generated by $0 with the DISPLAY_TESTS "
	echo "# set in the config"
	echo 
fi

# XXX Add a loop for number of sessions : 500, 1000
# XXX Burst too.
# XXX H/A




disp_count=1 
LOGDIR_HEAD=${LOGDIR}
done_run=false
# XXX For display and plot we need to get the test name from the number instead
# of going over the loop just for that.
for mode in $NIC_MODES
do
	LOGDIR=${LOGDIR_HEAD}/${mode}
	# mkdir -p $LOGDIR
	if [ $RUN_TESTS = "yes" ]
	then
		if [ $mode = "pt" ] ; then
			RPVM=$RPVM_PT
		elif [ $mode = "ct" ] ; then
			RPVM=$RPVM_CT
		else
			RPVM=$RPVM_SRIOV
		fi
	else
		echo 
		echo "# NiC mode : $mode"
		echo "------------------------------------------------------------------"
	fi
	for profile in $TEST_PROFILE
	do
		LOGDIR=${LOGDIR_HEAD}/${mode}_${profile}
		if [ $RUN_TESTS = "yes" ]
		then
			mkdir -p $LOGDIR
			startup_vm $RPVM
			cleanup $mode
			log_run
			setup_vm
			# XXX mlnx_tune has some issues with 
			# "AttributeError: 'NoneType' object has no attribute 'report_status'"
			# when run in the SRIOV VM.
			if [ $mode = "pt" ]
			then
				ssh $RP mlnx_tune -p $profile > $LOGDIR/mlnx_tune.log 2>&1
			fi
		else
			echo
		fi
		for cpu_binding in $CPU_BINDINGS
		do
			LOGDIR=${LOGDIR_HEAD}/${mode}_${profile}_${cpu_binding}
			if [ $RUN_TESTS = "yes" ]
			then
				#mkdir -p $LOGDIR
				host_vm_cpu_binding $cpu_binding
			fi
			for  cpu_affinity in $CPU_AFFINITIES
			do
				LOGDIR=${LOGDIR_HEAD}/${mode}_${profile}_${cpu_binding}_${cpu_affinity}
				if [ $RUN_TESTS = "yes" ]
				then
					#mkdir -p $LOGDIR
					rp_irq_affinity $mode $cpu_affinity
				fi
				# echo "$mode, $profile, $cpu_binding, $cpu_affinity, $test"
				for t in $TESTS
				do
					if [ $DISPLAY_TESTS = "yes" ]
					then
						echo "$disp_count: $mode, $profile, $cpu_binding, $cpu_affinity, $t"
					elif [ $PLOT_RESULTS = "yes" ]
					then
						LOGDIR=${mode}_${profile}_${cpu_binding}_${cpu_affinity}_${t}
						if [ $TEST_TO_PLOT != $disp_count ]
						then
							disp_count=$((disp_count+1))
							continue
						fi
						# plotLogs $LOGDIR
						done_run="true"
						break
					else
						LOGDIR=${LOGDIR_HEAD}/${mode}_${profile}_${cpu_binding}_${cpu_affinity}_${t}
						mkdir -p $LOGDIR
						if [ -n "$TEST_TO_RUN" ]
						then
							if [ $TEST_TO_RUN != $disp_count ]
							then
								disp_count=$((disp_count+1))
								continue
							fi
						fi
						setup_tests $mode $t
						#if [ $cpu_affinity = "8" ]
						#then
						#	echo "Quitting..."
						#	exit
						#fi
						echo "Running test $disp_count, $mode, $profile, $cpu_binding CPU, $cpu_affinity, $t"
						runTest
						runMetrics $mode
						cleanup $mode
						if [ -n "$TEST_TO_RUN" ]
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
		#if [ $RUN_TESTS = "yes" ]
		#then
		#	shutdown_vm $RPVM
		#fi
		if [ $done_run = "true" ]
		then
			break
		fi
	done
	if [ $done_run = "true" ]
	then
		break
	fi
	if [ $RUN_TESTS = "yes" ]
	then
		# log_after
		shutdown_vm $RPVM
	fi
done

# Tar the log file
if [ $RUN_TESTS = "yes" ]
then
	if [ "$(ls -A $LOGDIR_HEAD)" ]
	then
		echo "Tar'ing $LOGDIR_HEAD as $LOGDIR_HEAD.tar.gz"
		tar -czf $LOGDIR_HEAD.tar.gz $LOGDIR_HEAD > /dev/null 2>&1
	fi
fi

if [ $PLOT_RESULTS = "yes" ]
then
	# echo "Plotting $PLOT_DIR $LOGDIR $TEST_TO_PLOT"
	plotLogs $PLOT_DIR $LOGDIR $TEST_TO_PLOT
fi
#log_run
