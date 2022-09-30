#!/bin/bash

bash /root/setup-tcp-xdp.sh

echo "Entering sleep... (success)"
trap : TERM INT

# Sleep forever.
sleep 2147483647 & wait
