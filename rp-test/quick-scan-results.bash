#!/bin/bash

set -u
set -e

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
