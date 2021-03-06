package main

import (
	"fmt"
	"log"
	"os"
	"time"
	"strconv"
	"github.com/safchain/ethtool"
)


type OneIntf struct {
	e  *ethtool.Ethtool
	intf		string
	deltaT		int
	rx_pkts_nic1 uint64
	rx_packets1 uint64
	tx_pkts_nic1 uint64
	tx_packets1 uint64
	rx_pkts_nic2 uint64
	rx_packets2 uint64
	tx_pkts_nic2 uint64
	tx_packets2 uint64
	rx_dropped1 uint64
	rx_dropped2 uint64
	tx_dropped1 uint64
	tx_dropped2 uint64
}

func (self *OneIntf) Init() {
	//init
	e, err := ethtool.NewEthtool()
	if err != nil {
		panic(err.Error())
	}
	//defer e.Close()
	self.e = e

}

func (self *OneIntf) Collect(c int) {
	e, err := ethtool.NewEthtool()
	if err != nil {
		panic(err.Error())
	}
	self.e = e
	defer self.e.Close()

	stats, err := self.e.Stats(self.intf)
        if err != nil {
                panic(err.Error())
        }
	if c == 1 {
		self.rx_pkts_nic1   = stats["rx_pkts_nic"]
		self.rx_packets1    = stats["rx_packets"]
		self.tx_pkts_nic1   = stats["tx_pkts_nic"]
		self.tx_packets1    = stats["tx_packets"]
		self.rx_dropped1     = stats["rx_dropped"]	
		self.tx_dropped1     = stats["tx_dropped"]	
	}
	if c == 2 {
		self.rx_pkts_nic2   = stats["rx_pkts_nic"]
		self.rx_packets2    = stats["rx_packets"]
		self.tx_pkts_nic2   = stats["tx_pkts_nic"]
		self.tx_packets2    = stats["tx_packets"]
		self.rx_dropped2     = stats["rx_dropped"]	
		self.tx_dropped2     = stats["tx_dropped"]	
	}

}

func main() {


	if len(os.Args) < 4 {
		log.Fatal("Please specify both interfaces and a delta in seconds")
	}


	intfs := make([]OneIntf, 0)
	numIntfs := 2
	deltaT, _ := strconv.Atoi(os.Args[3])

	for i:=0; i < numIntfs;  i++ {

		intf := OneIntf{intf: os.Args[i+1], deltaT: deltaT}
		intfs = append(intfs, intf)
	}
	for {
		for i:=0; i < numIntfs;  i++ {
		       go intfs[i].Collect(1)
		}
		time.Sleep(time.Duration(deltaT)*1000 * time.Millisecond)
		for i:=0; i < numIntfs;  i++ {
		       go intfs[i].Collect(2)
		}
		time.Sleep(time.Duration(1)*100 * time.Millisecond)
		fmt.Println(time.Now())
		fmt.Println(intfs[0].intf, "delta rx=", intfs[0].rx_packets2-intfs[0].rx_packets1, intfs[0].rx_packets2, intfs[0].rx_packets1)
		fmt.Println(intfs[1].intf, "delta tx=", intfs[1].tx_packets2-intfs[1].tx_packets1, intfs[1].tx_packets2, intfs[1].tx_packets1)
		fmt.Println("RX->TX:", (intfs[0].rx_packets2-intfs[0].rx_packets1)-(intfs[1].tx_packets2-intfs[1].tx_packets1))
		fmt.Println(intfs[0].intf, "delta NIC rx=", intfs[0].rx_pkts_nic2-intfs[0].rx_pkts_nic1, intfs[0].rx_pkts_nic2, intfs[0].rx_pkts_nic1)
		fmt.Println(intfs[1].intf, "delta NIC tx=", intfs[1].tx_pkts_nic2-intfs[1].tx_pkts_nic1, intfs[1].tx_pkts_nic2, intfs[1].tx_pkts_nic1)
		fmt.Println(intfs[0].intf, "delta rx dropped=", intfs[0].rx_dropped2-intfs[0].rx_dropped1, intfs[0].rx_dropped2, intfs[0].rx_dropped1)
		fmt.Println(intfs[1].intf, "delta tx dropped=", intfs[1].tx_dropped2-intfs[1].tx_dropped1, intfs[1].tx_dropped2, intfs[1].tx_dropped1)
	}

	time.Sleep(time.Duration(3)*1000 * time.Millisecond)
	select  {}

}
