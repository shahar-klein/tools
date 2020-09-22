#!/bin/bash

listP=${1:?need start}
listP=$@


for p in $listP
do
	nc -kluvw 0 $p &
	nc -klvnp $p &
done 

wait
