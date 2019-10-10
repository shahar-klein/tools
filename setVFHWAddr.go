package main

import (
        "fmt"
        "github.com/vishvananda/netlink"
	"os"
	"strconv"
)




func main() {

	args := os.Args
	fmt.Println(args)
	if len(args) < 4 {
		fmt.Println("Need VF PF and num vf to set")
		os.Exit(1)
	}
	vfDev := args[1]
	pfDev := args[2]
	vfNum, _ := strconv.Atoi(args[3])



	vfLink, err := netlink.LinkByName(vfDev)
        if err != nil {
                fmt.Println(err)
        }
	hwAddr := vfLink.Attrs().HardwareAddr

	pfLink, err := netlink.LinkByName(pfDev)
        if err != nil {
                fmt.Println(err)
        }
	vfHwAddr := pfLink.Attrs().Vfs[vfNum].Mac
	fmt.Println("Before Pf vf", vfNum, ":", vfHwAddr)


	fmt.Println("setting: ", hwAddr, " to PF:", pfDev, " VF:", vfNum)

	netlink.LinkSetVfHardwareAddr(pfLink, vfNum, hwAddr)

	pfLink, err = netlink.LinkByName(pfDev)
        if err != nil {
                fmt.Println(err)
        }
	vfHwAddr = pfLink.Attrs().Vfs[vfNum].Mac
	fmt.Println("After Pf vf", vfNum, ":", vfHwAddr)

}

