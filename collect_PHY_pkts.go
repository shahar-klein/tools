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
	rx_bytes1 uint64
	rx_packets1 uint64
	tx_bytes1 uint64
	tx_packets1 uint64
	rx_drops1 uint64
}

func (self *OneIntf) Collect() {

	stats, err := self.e.Stats(self.intf)
        if err != nil {
                panic(err.Error())
        }
	self.rx_bytes1   = stats["rx_bytes"]
	self.rx_packets1 = stats["rx_packets"]
	self.tx_bytes1   = stats["tx_bytes"]
	self.tx_packets1 = stats["tx_packets"]
	self.rx_drops1   = stats["rx_out_of_buffer"]
	fmt.Println("rx_packets:", self.rx_packets1)



}


func (self *OneIntf) Init() {
	//init
	e, err := ethtool.NewEthtool()
	if err != nil {
		panic(err.Error())
	}
	//defer self.e.Close()
	self.e = e
	//time.Sleep(time.Duration(self.deltaT)*1000 * time.Millisecond)

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
	//fmt.Println(intfs[0].intf, intfs[1], deltaT)
	//for {
	for i:=0; i < numIntfs;  i++ {
		intfs[i].Init()
	}
	for i:=0; i < numIntfs;  i++ {
	       go intfs[i].Collect()
	}
	//}

	time.Sleep(time.Duration(3)*1000 * time.Millisecond)
	select  {}

}
