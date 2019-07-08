package main

import (
	"fmt"
	"log"
	"os"
	"time"

	"github.com/safchain/ethtool"
)

func humanRead(bytes uint64) (string){


        switch {
                case bytes > 1000000000:
                        return fmt.Sprintf("%.2f%s", float64(bytes)/1000000000, " G")
                case bytes > 1000000:
                        return fmt.Sprintf("%.2f%s", float64(bytes)/1000000, " M")
                case bytes > 1000:
                        return fmt.Sprintf("%.2f%s", float64(bytes)/1000, " K")
        }

	return fmt.Sprint(bytes)

}


func GetStats(e  *ethtool.Ethtool, name string) (uint64, uint64, uint64, uint64, uint64) {
	stats, err := e.Stats(name)
        if err != nil {
                panic(err.Error())
        }
	return  stats["rx_bytes"], stats["rx_packets"], stats["tx_bytes"], stats["tx_packets"], stats["rx_out_of_buffer"]


}


type OneIntf struct {
	e  *ethtool.Ethtool
	intf		string
	display_rx_bytes uint64
	display_rx_packets uint64
	display_tx_bytes uint64
	display_tx_packets uint64
	display_rx_drops uint64
	rx_bytes uint64
	rx_packets uint64
	tx_bytes uint64
	tx_packets uint64
	rx_drops uint64
}

func (self *OneIntf) do() {

	stats, err := self.e.Stats(self.intf)
        if err != nil {
                panic(err.Error())
        }
	self.display_rx_bytes   = stats["rx_bytes"] - self.rx_bytes
	self.display_rx_packets = stats["rx_packets"] - self.rx_packets
	self.display_tx_bytes   = stats["tx_bytes"] - self.tx_bytes
	self.display_tx_packets = stats["tx_packets"] - self.tx_packets
	self.display_rx_drops   = stats["rx_out_of_buffer"] - self.rx_drops
	self.rx_bytes   = stats["rx_bytes"]
	self.rx_packets = stats["rx_packets"]
	self.tx_bytes   = stats["tx_bytes"]
	self.tx_packets = stats["tx_packets"]
	self.rx_drops   = stats["rx_out_of_buffer"]



}


func (self *OneIntf) mainLoop() {
	//init
	e, err := ethtool.NewEthtool()
	if err != nil {
		panic(err.Error())
	}
	defer self.e.Close()
	self.e = e
	stats, err := self.e.Stats(self.intf)
	self.rx_bytes   = stats["rx_bytes"]
	self.rx_packets = stats["rx_packets"]
	self.tx_bytes   = stats["tx_bytes"]
	self.tx_packets = stats["tx_packets"]
	self.rx_drops   = stats["rx_out_of_buffer"]

        if err != nil {
                panic(err.Error())
        }
	for {
		go self.do()
		time.Sleep(1000 * time.Millisecond)
	}

}

func main() {

	print("\033[H\033[2J")



	if len(os.Args) < 2 {
		log.Fatal("Please specify at least one interface")
	}


	baseLine := 4

	pos := fmt.Sprintf("\033[%d;14H", baseLine)
	fmt.Printf(pos)
	fmt.Println("    RX                                   TX                  ERRORS")


	intfs := make([]OneIntf, 0)
	numIntfs := len(os.Args)-1

	for i:=0; i < numIntfs;  i++ {

		intf := OneIntf{intf: os.Args[i+1]}
		intfs = append(intfs, intf)
	}
	for i:=0; i < numIntfs;  i++ {
		go intfs[i].mainLoop()
	}

	for {
		time.Sleep(1000 * time.Millisecond)
		line := baseLine+1;
		pos = fmt.Sprintf("\033[%d;0H", line)
		fmt.Printf(pos)
		for i := 0 ; i < numIntfs; i++ {
			fmt.Printf("%s      %sbits [%sPPS]         %sbits [%sPPS]        %s DropsPerSecond                                   .\n", intfs[i].intf, humanRead(8*intfs[i].display_rx_bytes), humanRead(intfs[i].display_rx_packets), humanRead(8*intfs[i].display_tx_bytes), humanRead(intfs[i].display_tx_packets),  humanRead(intfs[i].display_rx_drops))
		}
	}


	select  {}

}
