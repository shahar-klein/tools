#!/bin/bash
apt-get update
apt -y install curl
curl -s https://cfc948207fe44a24b97ea67176d072110423abc962fd93e0:@packages.nvidia.com/install/repositories/sdn/mlnx-linux-5-4-drop1/script.deb.sh | bash
apt install linux-image-5.4.31
apt install linux-headers-5.4.31
apt install linux-libc-dev
#reboot
wget https://www.mellanox.com/downloads/ofed/MLNX_OFED-5.2-2.2.0.0/MLNX_OFED_LINUX-5.2-2.2.0.0-ubuntu18.04-x86_64.tgz
tar xvfz MLNX_OFED_LINUX-5.2-2.2.0.0-ubuntu18.04-x86_64.tgz
cd  MLNX_OFED_LINUX-5.2-2.2.0.0-ubuntu18.04-x86_64/
echo "reboot now"
#./mlnxofedinstall
~

