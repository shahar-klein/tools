#!/bin/bash
# XXX reference : http://babilonline.blogspot.com/2008/05/jitter.html
if [ -z $1 ]
then
 echo "[+] $0 capture.pcap "
 exit
fi

if [ ! -z $2 ]
then
 limit=$2
else
 limit=0
fi

echo $3 $4

#tshark -r $1 | grep "1.1.1.1 -> 1.1.1.2" | grep -v "ICMP"| grep -i "\[Data\] Seq\|UDP\|TCP" | awk '{if(NR==1){f=$2;s=$2};print ($2-f),($2-s)*1000;s=$2;}' > jitter.tmp
tshark -r $1 | grep "$3 → $4" | grep -v "ICMP"| grep -i "\[Data\|UDP\|TCP" | awk '{if(NR==1){f=$2;s=$2};print ($2-f),($2-s)*1000;s=$2;}' > jitter.tmp

#cat jitter.tmp | awk '{ k=$2-s ; if(($2-s)<0){k=($2-s)*(-1)} ; t=t+k ; print $1,$2-s,t/NR ; s=$2}' > jitter.txt ## mixed
cat jitter.tmp | awk -v l=$limit '{ k=$2-s ; if(($2-s)<0){k=($2-s)*(-1)} ; t=t+k ; if(k>l){print $1,k,t/NR}; s=$2}' > jitter.txt ## all positive

avg=`tail -n1 jitter.txt | awk '{print $3}'`

echo 'set style data points' > jitter.gp
echo 'set nogrid' >> jitter.gp

echo 'set style line 1 lt 1 lw 2' >> jitter.gp
echo 'set style line 2 lt 2 lw 2' >> jitter.gp
echo 'set style line 3 lt 3 lw 5' >> jitter.gp
echo 'set style line 4 lt 3 lw 1' >> jitter.gp
echo 'set style line 5 lt 3 lw 2' >> jitter.gp
echo 'set style line 6 lt 3 lw 1' >> jitter.gp
echo 'set style line 7 lt 17 lw 2' >> jitter.gp
echo 'set style line 8 lt 17 lw 4' >> jitter.gp

echo '#set logscale y' >> jitter.gp
echo '#set xrange[1:180]' >> jitter.gp
echo '#set yrange[1:2]' >> jitter.gp
echo '#set samples 2000' >> jitter.gp
echo '#set xtics 50' >> jitter.gp
echo '#set ytics 50' >> jitter.gp

echo 'set xlabel  "Time (sec)"' >> jitter.gp
echo 'set ylabel  "Kbit/s"' >> jitter.gp

echo 'plot "jitter.txt" using 1:($2/1) title "jitter ('$avg'ms)" with impulses ls 6' >> jitter.gp
echo '#plot "jitter.txt" using 1:($2/1) title "jitter ('$avg'ms)" with lines ls 6' >> jitter.gp
echo '#replot "jitter.txt" using 1:($3/1) title "cumul jitter ('$avg'ms)" with lines ls 8' >> jitter.gp

echo 'set encoding iso_8859_1' >> jitter.gp
echo 'set term post color "Helvetica" 18' >> jitter.gp
echo 'set output "jitter.eps"' >> jitter.gp
echo 'replot' >> jitter.gp

echo 'set term png' >> jitter.gp
echo 'set output "jitter.png"' >> jitter.gp
echo 'replot' >> jitter.gp

gnuplot jitter.gp 2>&1 1>/dev/null
qiv jitter.png &
