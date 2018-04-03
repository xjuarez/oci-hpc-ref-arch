#!/bin/bash

# PARM: 1="0" turn off hyper threading, "1" turn it on.

yum install -y -q stress

if [[ $# -ne 1 ]]; then
    echo 'One argument required. 0 to turn off hyper-threading or'
    echo '1 to turn hyper-threading back on'
    exit 1
fi

echo Thread pairs before change
cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list | sort --unique --numeric-sort
echo

for k in `seq 52 103`; do 
    echo $1 > /sys/devices/system/cpu/cpu$k/online;
done

grep "" /sys/devices/system/cpu/cpu*/topology/core_id

grep -q '^flags.*[[:space:]]ht[[:space:]]' /proc/cpuinfo && \
    echo "Hyper-threading is supported"

grep -E 'model|stepping' /proc/cpuinfo | sort -u

echo Thread pairs after change
cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list | sort --unique --numeric-sort
echo

stress --cpu 52 --io 1 --vm 1 --vm-bytes 128M --timeout 10s
