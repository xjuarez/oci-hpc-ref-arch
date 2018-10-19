#!/bin/bash
MYUSER=$1
runuser -l $MYUSER -c "pdsh -w ^/home/$MYUSER/hostfile hostname > /home/$MYUSER/hostnames"
cat /home/$MYUSER/hostnames >> /etc/hosts
sed -i 's/: / /g' /etc/hosts
