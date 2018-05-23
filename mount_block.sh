#!/bin/bash
#arguments [iqn] [ipv4]
export IQN=$1
export IPV4=$2

sudo iscsiadm -m node -o new -T $IQN -p $IPV4:3260
sudo iscsiadm -m node -o update -T $IQN -n node.startup -v automatic
sudo iscsiadm -m node -T $IQN -p $IPV4:3260 -l

sudo yum install parted
sudo parted -l | grep Error
lsblk
sudo parted /dev/sdb mklabel gpt
sudo parted -a opt /dev/sdb mkpart primary ext4 0% 100%
sudo mkfs.ext4 -L datapartition /dev/sdb1
sudo mkdir -p /mnt/blk
sudo mount -o defaults /dev/sdb1 /mnt/blk
sudo nano /etc/fstab
/dev/sdb1 /mnt/blk ext4 defaults 0 2
