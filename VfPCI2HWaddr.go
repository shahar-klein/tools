package main

import (
        "fmt"
	"os"
	"strings"
	"io/ioutil"
        "github.com/vishvananda/netlink"
)

// Given a VF's PCI address of the form 0000:8b:00.2, return the MAC address.
// Note "0000" is required in the input PCI BDF.
// This doesn't support PF currently.


//
// XXX-Maybe there is a better way to do this. Generalize this, might be too
// Mellanox specific.
//
func getVFNumForDevice(pciaddr, pfname string) (int, error) {

	// XXX-Generalize this
	for fn := 0; fn <= 8; fn++ {
		vfDir := fmt.Sprintf("/sys/class/net/%s/device/virtfn%d/uevent", pfname, fn)
		read, err := ioutil.ReadFile(vfDir)
		if err != nil {
			return 0,fmt.Errorf("Can't read File %s: %v", vfDir, err)
		}
		if strings.Contains(string(read), pciaddr) {
			return fn, nil
		}
	}
	return 0,fmt.Errorf("Didn't find VF number for %s, %s", pciaddr, pfname)
}

//
// Given a PCI addres, gets its PF and VF num, and get the MAC address
// from them.
// XXX-Move to a lib.
//
func getMACForDevice (pciaddr string) (string, error) {
	// Get PF name
	pciDir := fmt.Sprintf("/sys/bus/pci/devices/%s/physfn/net", pciaddr)
	files, err := ioutil.ReadDir(pciDir)
	if err != nil {
		return "",fmt.Errorf("Error reading %s for PF name", pciDir)
	}

	// Get VF num. XXX maybe there is a better way to do this.
	// XXX Only one file in this dir with the PF name
	pfname := files[0].Name()
	vfnum, err := getVFNumForDevice(pciaddr, pfname)
	if err != nil {
		return "",fmt.Errorf("Error geting VF num for %s", pciDir)
	}

	pfLink, err := netlink.LinkByName(pfname)
	if err != nil {
		return "",fmt.Errorf("Error geting link for PF %s: %v", pfname, err)
	}
	macAddr := pfLink.Attrs().Vfs[vfnum].Mac
	return macAddr.String(), nil
}

func main() {
	args := os.Args
	fmt.Println(args)
	if len(args) < 2 {
		fmt.Println("Need VF PCI addr for which HW address is desired")
		os.Exit(1)
	}
	// XXX-Check if the PCI addr corresponds to a VF
	pciAddr := args[1]
	macAddr, err := getMACForDevice(pciAddr)
	if err != nil {
		fmt.Println("Error getting MAC address for PCI %s: %v", pciAddr, err)
	}
	fmt.Println("HW address for PCI addr", pciAddr, ":", macAddr)
}

