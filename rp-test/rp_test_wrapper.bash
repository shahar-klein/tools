#!/bin/bash


# This is a wrapper for rp_test.
# you can use this wrapper to run a single, subset or all of the rp tests.
# All the cases are listed in rp_test.runs
# run this wrapper with a space separated case list or all
# Examplple:
# bash rp_test_wrapper.bash case_2
# bash rp_test_wrapper.bash case_1 case_2 case_41
# bash rp_test_wrapper.bash all


# Each RP test is given a set of params:
# test name
# mode: pt, sriov, bm
# profile: one of Mellanox preset performance profiles: IP_FORWARDING_MULTI_STREAM_0_LOSS IP_FORWARDING_MULTI_STREAM_THROUGHPUT IP_FORWARDING_MULTI_STREAM_PACKET_RATE
# cpu binding policy: pinned or dangling
# cpu affinity policy: one CPU per channel or one CPU per pair of(RX, TX) channels: 4, 8
# Datapath profile: linux_fwd linux_fwd_nat ovs_fwd ovs_fwd_offload ovs_fwd_nat ovs_fwd_nat_offload ovs_fwd_ct ovs_fwd_ct_offload
# num sessions: how many sessions to run
# bw per session
#
# Example: rp_test.bash case_2 pt IP_FORWARDING_MULTI_STREAM_0_LOSS dangling 8 linux_fwd 100 20m
#

set -u
set -e


RUNS=rp_test.runs

# From the following possibilities
#MODES="pt sriov bm ha pt_multip"
#PROFILES="NONE IP_FORWARDING_MULTI_STREAM_0_LOSS IP_FORWARDING_MULTI_STREAM_THROUGHPUT IP_FORWARDING_MULTI_STREAM_PACKET_RATE"
#DATAPATHS="linux_fwd linux_fwd_nat ovs_fwd ovs_fwd_offload ovs_fwd_nat ovs_fwd_nat_offload ovs_fwd_ct ovs_fwd_ct_offload"
#NUM_SESSIONS="100 500 1000"
#CPU_AFFINITIES="4 8"
#CPU_BINDINGS="dangling pinned"

# Running the following subset
MODES="pt_multip"
PROFILES="NONE"
BUFFER_SIZE="8192"
CPU_BINDINGS="pinned"
CPU_AFFINITIES="8"
DATAPATHS="ovs_fwd_nat"
NUM_SESSIONS="500"
BANDWIDTH_PER_SESSION=20m

outline_all() {
	CASE=0
	for m in $MODES ; do
		for bs in $BUFFER_SIZE ; do
			for b in $CPU_BINDINGS ; do
				for a in $CPU_AFFINITIES ; do
					for d in $DATAPATHS ; do
						for n in $NUM_SESSIONS ; do
							CASE=$((CASE+1))
							echo case_${CASE} $m $bs $b $a $d $n $BANDWIDTH_PER_SESSION
						done
					done
				done
			done
		done
	done
}

CMD=$1
if [ $CMD = "list" ]; then
	outline_all
	exit
fi
shift
LOGDIR=$1
# Log file location
D=`date +%b-%d-%Y`
LOGDIR+=_$$
LOGDIR+=_$D
mkdir -p $LOGDIR >/dev/null 2>&1
outline_all > $LOGDIR/$RUNS
shift
CASES=$@
if [ $CASES = "all" ] ; then
	CASES=`grep case $LOGDIR/$RUNS | awk '{print $1}'`
fi
#echo $CASES

iptables-save > $LOGDIR/working.iptables.rules.$$
for CASE in $CASES ; do
	args=`grep -w $CASE $LOGDIR/$RUNS`
	# echo $args
	bash  rp_test.bash $LOGDIR $args
done
iptables-restore < $LOGDIR/working.iptables.rules.$$
rm $LOGDIR/working.iptables.rules.$$
echo "Taring $LOGDIR as ${LOGDIR}.tar.gz"
tar -czf ${LOGDIR}.tar.gz $LOGDIR > /dev/null 2>&1
rm -rf $LOGDIR > /dev/null 2>&1
