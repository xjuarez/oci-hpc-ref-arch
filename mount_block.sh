#!/bin/bash
#arguments [iqn] [ipv4]
export IQN=$1
export IPV4=$2

sudo iscsiadm -m node -o new -T $IQN -p $IPV4:3260
sudo iscsiadm -m node -o update -T $IQN -n node.startup -v automatic
sudo iscsiadm -m node -T $IQN -p $IPV4:3260 -l
