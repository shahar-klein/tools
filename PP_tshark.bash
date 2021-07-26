#tshark -n -r /tmp/RX12096.pcap -T fields -e frame.time_delta_displayed | cut -c1-6 | uniq -c | awk '{print $1}' | sort -n | uniq -c
In the pcap file, every line is a packet
frame.time_delta_displayed shows delta between packets in nano
so, for example in this sequence:
0.000432000
0.000033000
0.000037000
0.000020000
0.000031000
0.000240000
We can see the first packet cam 432000(432 micro seconds) nano after the prev one
and the second came 33000 nano (33 micro second) after the first one in this sequence and so on
We add cut -c1-6 which chamges the resolution to 100 micro second
so the same sequence looks like that now:
0.0004
0.0000
0.0000
0.0000
0.0000
0.0002
we can see that packets 2-5 arrived at the same 100 micro second window
so lets count them with uniq -c
      1 0.0004
      4 0.0000
      1 0.0002
and we don't need the delta field anymore, hence the awk '{print $1}'
and adding another sort -n | uniq -c
create a sorted histogram of 100 microsecond bursts:
2 bursts of one packet and one burst of four packets by 100 microsecond window
      2 1
      1 4
to sum up the packets and make sure the script is correct
tshark...  uniq -c | awk '{m = $1 * $2; print m ; T += m} END {print "T="T}'
