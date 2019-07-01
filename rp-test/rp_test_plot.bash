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


#plotLogs  case_1_11912_Jun-30-2019 pt_IP_FORWARDING_MULTI_STREAM_0_LOSS_pinned_4_linux_fwd_100 case1

plotLogs $1 $2 $3
