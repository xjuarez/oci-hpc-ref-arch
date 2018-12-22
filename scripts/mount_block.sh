#!/bin/bash
#arguments [operation] [iqn] [ipv4]
export IQN=$2
export IPV4=$3
export operation=$1

attach()
{
    iscsiadm -m node -o new -T $IQN -p $IPV4:3260
    iscsiadm -m node -o update -T $IQN -n node.startup -v automatic
    iscsiadm -m node -T $IQN -p $IPV4:3260 -l
}

mounter()
{

    yum -y -q install parted
    if [ `lsblk -d --noheadings | awk '{print $1}' | grep nvme0n1` = "nvme0n1" ]; then NVME=true; else NVME=false; fi
    for i in `lsblk -d --noheadings | awk '{print $1}'`
    do 
        if [ $i = "sda" ]; then  next
        else
            lsblk
            parted /dev/$i mklabel gpt
            parted -a opt /dev/$i mkpart primary ext4 0% 100%
            if $NVME; then 
                extension=$i\p1
            else 
                extension=$i\1
            fi
            mkfs.ext4 -L datapartition /dev/$extension          
            echo "/dev/$extension /mnt/blk$extension ext4 defaults 0 2" | tee -a /etc/fstab
            mkdir -p /mnt/blk$extension
        fi
    done
    mount -a
    df -h
}

if [ $1 = "attach" ]; then attach
elif [ $1 = "mount" ]; then mounter
else echo error; fi