#!/bin/bash

set -e

if test -f rp_test.config ; then
	. rp_test.config
else
	echo "Config file missing ... exiting"
fi

plotLogs() {
	dir=$1
	local test=$2
	testdir=$1/$2
	title=`echo $test | tr -s "_" ","`
	which=$3
	#if [ -z GNUPLOT_TERMINAL ]
	#then
	#	GNUPLOT_TERMINAL=qt
	#fi
	bw_plot=1
	cpu_plot=1
	if [ -n $which -a $which = "cpu" ]; then
		bw_plot=0
	fi
	if [ -n $which -a $which = "bw" ]; then
		cpu_plot=0
	fi
	if [ $bw_plot -eq 1 ] ; then
		gnuplot -persist <<-EOFMarker
		
			set multiplot layout 1,2 rowsfirst title "$title"
	
			# Range assuming 5-15Gbps
			set yrange [625000000:1875000000]
			set label 1 'Bytes/sec' at graph .3,.1
			set ylabel "Bandwidth : Range 5 - 15 Gb/sec"
			plot "$testdir/${RP_PRIV_LEG_DEV}.tput" using 1:2 with lines title "RX Bytes", \
				"$testdir/${RP_PUB_LEG_DEV}.tput" using 1:2 with lines title "TX Bytes"
	
			# These are packets, so use 1000000 as the upper limit, as an estimate.
			set yrange [0:1000000]
			set label 1 'Packets/sec' at graph .3,.1
			set ylabel "Number of packets"
			plot "$testdir/${RP_PRIV_LEG_DEV}.dropped" using 1:2 with lines title "RX Packets Dropped", \
				"$testdir/${RP_PUB_LEG_DEV}.dropped" using 1:2 with lines title "TX Packets Dropped"
	
	
			unset multiplot
		EOFMarker
	fi
	if [ $cpu_plot -eq 1 ] ; then
		gnuplot -persist <<-EOFMarker
			set title noenhanced
			set multiplot layout 4,2 rowsfirst title "$title"
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
	fi
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


#plotLogs  case_1_11912_Jun-30-2019 pt_IP_FORWARDING_MULTI_STREAM_0_LOSS_pinned_4_linux_fwd_100 [cpu|bw]
#plotLogs case_1_11912_Jun-30-2019 match linux_fwd_100 [cpu|bw]
# plotLogs case_1_11912_Jun-30-2019 all [cpu|bw]
if [ $2 = "all" ] ; then
	for test in `ls $1` ; do
		if [ $test = "main.log" -o $test = "rp_test.runs" ] ; then
			continue
		fi
		plotLogs $1 $test $2
	done
elif [ $2 = "match" ]; then
	for test in `ls $1 | grep $3` ; do
		if [ $test = "main.log" -o $test = "rp_test.runs" ] ; then
			continue
		fi
		plotLogs $1 $test $4 
	done
else
	plotLogs $1 $2 $3
fi
