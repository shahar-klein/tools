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

MODES="pt sriov bm"
PROFILES="IP_FORWARDING_MULTI_STREAM_0_LOSS IP_FORWARDING_MULTI_STREAM_THROUGHPUT IP_FORWARDING_MULTI_STREAM_PACKET_RATE"
CPU_BINDINGS="pinned dangling"
CPU_AFFINITIES="4 8"
DATAPATHS="linux_fwd linux_fwd_nat ovs_fwd ovs_fwd_offload ovs_fwd_nat ovs_fwd_nat_offload ovs_fwd_ct ovs_fwd_ct_offload"
NUM_SESSIONS="100 500 1000"
outline_all() {
	CASE=0
	for m in $MODES ; do
		for p in $PROFILES ; do
			for b in $CPU_BINDINGS ; do
				for a in $CPU_AFFINITIES ; do
					for d in $DATAPATHS ; do
						for n in $NUM_SESSIONS ; do
							CASE=$((CASE+1))
							echo case_${CASE} $m $p $b $a $d $n 20m
						done
					done
				done
			done
		done
	done
}


#outline_all

RUNS=rp_test.runs
CASES=$@
if [ $CASES = "all" ] ; then
	CASES=`grep case $RUNS | awk '{print $1}'`
fi
echo $CASES

for CASE in $CASES ; do
	args=`grep -w $CASE $RUNS`
	echo $args
	bash rp_test.bash $args
done





