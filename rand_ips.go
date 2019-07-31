package main

import (
	"fmt"
	"net"
	"time"
	"math/rand"
	"log"
	"os"
	//"strings"
	"strconv"
	//"runtime"
	"encoding/binary"
)

func ip2int(ip net.IP) uint32 {
	if len(ip) == 16 {
		return binary.BigEndian.Uint32(ip[12:16])
	}
	return binary.BigEndian.Uint32(ip)
}

func int2ip(nn uint32) net.IP {
	ip := make(net.IP, 4)
	binary.BigEndian.PutUint32(ip, nn)
	return ip
}

var seededRand *rand.Rand = rand.New(
  rand.NewSource(time.Now().UnixNano()))

func main() {

        if len(os.Args) != 4 {
                log.Fatal("Please enter begin end num")
        }
	begin := os.Args[1]
	beginN := ip2int(net.ParseIP(begin))
	end := os.Args[2]
	endN := ip2int(net.ParseIP(end))
	numIPs, _ := strconv.Atoi(os.Args[3])
//	fmt.Println("Begin:", begin, "End:", end, "Num IPs:", numIPs)
	for i:=0; i < numIPs;  i++ {
		ipN := (seededRand.Uint32() % (endN - beginN)) + beginN
		ip := int2ip(ipN)
		fmt.Println(ip)
	}


}
