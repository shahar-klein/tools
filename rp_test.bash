#!/bin/bash

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

PRIV_NET="5.5.5.0/24"
PUB_NET="20.20.20.0/24"

LOADER=10.0.0.147
LOADER_DEV=ens2
LOADER_IP=5.5.5.5

INITIATOR=10.0.0.148
INITIATOR_DEV=ens2
INITIATOR_IP=20.20.20.20

RPVM=rp
RP=192.168.122.5
RP_PRIV_LEG_IP=5.5.5.1
RP_PRIV_LEG_DEV=enp4s0


RP_PUB_LEG_IP=20.20.20.100
RP_PUB_LEG_DEV=enp7s0


TEST=${1:?test name not set}

D=`date +%b-%d-%Y`
LOG=$TEST
LOG+=_$$
LOG+=_$D
echo $LOG
mkdir $LOG
LOG=$LOG/$LOG.main.log

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

cmdbg() {

	"${$1}" &>/dev/null &disown
}

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
	set +e
	logCMD "ssh $LOADER ip route add $PUB_NET"
	logCMD "ssh $INITIATOR ip route add $PRIV_NET"
	set -e
	#iptables
	log "Clean ip tables"
	logCMD "ssh $RP iptables -F"
	logCMD "ssh $RP iptables -t nat -F"
	#ovs
	log "Clean OVS flows"
	logCMD "ssh $RP ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br"

	ssh $LOADER pkill gonoodle
	ssh $INITIATOR pkill gonoodle
}

initTest() {
	#git pull?
	#init the RP depending on the datapath/cores/affinity etc
	logCMD "ssh $RP sysctl -w net.ipv4.ip_forward=1"
	logCMD "ssh $LOADER ip route add $PUB_NET via $RP_PRIV_LEG_IP dev $LOADER_DEV"
	logCMD "ssh $INITIATOR ip route add $PRIV_NET via $RP_PUB_LEG_IP dev $INITIATOR_DEV"
	#add routing rules
}

runTest() {
	#start loader
	cmdbg "ssh $LOADER /root/ws/git/gonoodle/gonoodle -u -c $INITIATOR_IP --rp loader -C 10 -R 1 -M 1 -b 22m -p 7000 -L :12000 -l 1000 -t 60 &"
	sleep 1
	cmdbg "ssh $INITIATOR /root/ws/git/gonoodle/gonoodle -u -c $LOADER_IP --rp initiator -C 10 -R 10 -M 1 -b 1k -p 12000 -L :7000 -l 1000 -t 1000 &"

}

### main ###

setup
cleanup
#log_before
initTest
runTest

sleep 100




