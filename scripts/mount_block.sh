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

mount()
{
    yum -y -q install parted
    sleep 30
    for i in `lsblk -d --noheadings | awk '{print $1}'`
    do 
        if [ $i = "sda" ]; then  break
        else
            lsblk
            parted /dev/$i mklabel gpt
            parted -a opt /dev/$i mkpart primary ext4 0% 100%
            mkfs.ext4 -L datapartition /dev/$i\1
            mkdir -p /mnt/blk$i
            echo "/dev/$i"1" /mnt/blk$i ext4 defaults 0 2" | tee -a /etc/fstab
        fi
    done
    mount -a
}

$operation