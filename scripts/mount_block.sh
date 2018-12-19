#!/bin/bash
#arguments [iqn] [ipv4]
export IQN=$1
export IPV4=$2

iscsiadm -m node -o new -T $IQN -p $IPV4:3260
iscsiadm -m node -o update -T $IQN -n node.startup -v automatic
iscsiadm -m node -T $IQN -p $IPV4:3260 -l

sleep 30

yum -y -q install parted
parted -l | grep Error
lsblk
parted /dev/sdb mklabel gpt
parted -a opt /dev/sdb mkpart primary ext4 0% 100%
mkfs.ext4 -L datapartition /dev/sdb1
mkdir -p /mnt/blk
mount -o defaults /dev/sdb1 /mnt/blk
echo "/dev/sdb1 /mnt/blk ext4 defaults 0 2" | tee -a /etc/fstab
