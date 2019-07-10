#!/bin/bash

set -e

if test -f rp_test.config ; then
	. rp_test.config
else
	echo "Config file missing ... exiting"
fi

compute_average() {
	file=$1
	time=$LOG_DURATION
	local avgbw=0
	for i in `cat $file | cut -d " " -f2`; do
		cum=$((total+$i))
	done
	bw=$((cum/time))
	echo $avgbw
}

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
	if [ ! -z $which -a $which = "cpu" ]; then
		bw_plot=0
	fi
	if [ ! -z $which -a $which = "bw" ]; then
		cpu_plot=0
	fi
	time=0
	rxavgbw=0
	txavgbw=0
	rxdrop=0
	txdrop=0

	cum=0
	for i in `cat $testdir/${RP_PRIV_LEG_DEV}.tput | cut -d " " -f2`; do
		cum=$((cum+$i))
		time=$((time+1))
	done
	rxavgbw=$((cum/time))
	rxavgbwps=$((rxavgbw/1000000))
	rxavgbwbps=$((rxavgbw*8))
	rxavgbwbps=$((rxavgbwbps/1000000))

	cum=0
	time=0
	for i in `cat $testdir/${RP_PUB_LEG_DEV}.tput | cut -d " " -f2`; do
		cum=$((cum+$i))
		time=$((time+1))
	done
	txavgbw=$((cum/time))
	txavgbwps=$((txavgbw/1000000))
	txavgbwbps=$((txavgbw*8))
	txavgbwbps=$((txavgbwbps/1000000))

	if [ $bw_plot -eq 1 ] ; then
		gnuplot -persist <<-EOFMarker
		
			set multiplot layout 1,2 rowsfirst title "$title"
	
			# Range assuming 5-15Gbps
			set yrange [625000000:1875000000]
			set label 1 'Bytes/sec' at graph .3,.1
			set label 2 '[RX Avg : $rxavgbwbps Mbps]' at graph 0.005,.875
			set label 3 '[TX Avg : $txavgbwbps Mbps]' at graph 0.005,.825
			set ylabel "Bandwidth : Range 0.625 - 1.875 GB/s [5 - 15 Gb/sec]"
			plot "$testdir/${RP_PRIV_LEG_DEV}.tput" using 1:2 with lines title "RX Bytes", \
				"$testdir/${RP_PUB_LEG_DEV}.tput" using 1:2 with lines title "TX Bytes"
	
			# These are packets, so use 1000000 as the upper limit, as an estimate.
			unset label
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
			set multiplot layout 10,2 rowsfirst title "$title"
			set yrange [0:100]
			plot "${testdir}/0.util" using 1:2 with lines title "CPU 0"
			plot "${testdir}/1.util" using 1:2 with lines title "CPU 1"
			plot "${testdir}/2.util" using 1:2 with lines title "CPU 2"
			plot "${testdir}/3.util" using 1:2 with lines title "CPU 3"
			plot "${testdir}/4.util" using 1:2 with lines title "CPU 4"
			plot "${testdir}/5.util" using 1:2 with lines title "CPU 5"
			plot "${testdir}/6.util" using 1:2 with lines title "CPU 6"
			plot "${testdir}/7.util" using 1:2 with lines title "CPU 7"
			plot "${testdir}/8.util" using 1:2 with lines title "CPU 8"
			plot "${testdir}/9.util" using 1:2 with lines title "CPU 9"
			plot "${testdir}/10.util" using 1:2 with lines title "CPU 10"
			plot "${testdir}/11.util" using 1:2 with lines title "CPU 11"
			plot "${testdir}/12.util" using 1:2 with lines title "CPU 12"
			plot "${testdir}/13.util" using 1:2 with lines title "CPU 13"
			plot "${testdir}/14.util" using 1:2 with lines title "CPU 14"
			plot "${testdir}/15.util" using 1:2 with lines title "CPU 15"
			plot "${testdir}/16.util" using 1:2 with lines title "CPU 16"
			plot "${testdir}/17.util" using 1:2 with lines title "CPU 17"
			plot "${testdir}/18.util" using 1:2 with lines title "CPU 18"
			plot "${testdir}/19.util" using 1:2 with lines title "CPU 19"
			unset multiplot
		EOFMarker
	fi

}
quick_scan_results_dir() {

	echo ""
	echo ""
	echo ""
	echo ""
	
	SCANDIR=${1:?Missing result dir as argument}
	
	for DIR in `ls -tr -d $SCANDIR/*/` ; do
		DEVS=`ls $DIR/*.tput | xargs -r -l basename`
		D=`basename $DIR`
		echo $D
		for DEV in $DEVS ; do
			DEVP=`echo $DEV| cut -f1 -d.`
			echo -n $DEVP":"
			cat $DIR/$DEV | awk '{sum+=$2} END {{BW=sum*8/(NR*1000000000)} if (BW < 1) {printf("\033[31m") }{printf(" %.2f GBit/s. ", BW)} {printf("\033[37m")}}' 
		done
		cat $DIR/*.idle |  awk '{sum+=$2} END {printf("Total CPU Usage: %.2f%. ", 100-sum/NR)}'
		cat $DIR/*.guest |  awk '{sum+=$2} END {printf("Guest CPU Usage: %.2f%. ", sum/NR)}'
		cat $DIR/*.dropped | awk '{sum+=$2} END {if ( sum > 0 ) {print "\033[31m Dropps/Errors: "sum "\033[37m"} else {print "\033[32mDropps/Errors: "sum "\033[37m"} }'
		echo ""
	done
}

if [ $1 = "quick" ] ; then
	shift
	quick_scan_results_dir $@
fi

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

