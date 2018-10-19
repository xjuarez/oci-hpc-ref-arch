#!/bin/bash
#only on the head node, being run as sudo

MYUSER=$1
runuser -l $MYUSER -c "pdsh -w ^/home/$MYUSER/hostfile hostname > /home/$MYUSER/hostnames"
cat /home/$MYUSER/hostnames >> /etc/hosts
sed -i 's/: / /g' /etc/hosts
cp /etc/hosts /mnt/blk/share/hosts
runuser -l $MYUSER -c "pdsh -w ^/home/$MYUSER/hostfile sudo cp /mnt/blk/share/hosts /etc/hosts"
