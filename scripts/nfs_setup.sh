#!/bin/bash
#PASS NFS HOST IP as ARGUMENT 1 
IPPRE=$1
IP=`hostname -i`
localip=`echo $IP | cut --delimiter='.' -f -3`


install_nfsserver()
{
  #Setup the NFS server
  nmap -p 80 $localip.0/20 | grep $localip | awk '{ print $5 }'> /home/opc/hostfile
  localip=`echo $IP | cut --delimiter='.' -f -3`
  mkdir -p /mnt/blk/share
  echo "/mnt/blk/share $localip.0/20(rw,sync,no_root_squash,no_all_squash)" | tee -a /etc/exports
  systemctl enable rpcbind
  systemctl enable nfs-server
  systemctl enable nfs-lock
  systemctl enable nfs-idmap
  systemctl start rpcbind
  systemctl start nfs-server
  systemctl start nfs-lock
  systemctl start nfs-idmap
  systemctl restart nfs-server
  chmod 777 /mnt/blk/share
}

install_nfsclient()
{
  sleep 60
  nmap -p 80 $localip.0/20 | grep $localip | awk '{ print $5 }'> /home/opc/hostfile
  mkdir -p /mnt/blk/share
  systemctl enable rpcbind
  systemctl enable nfs-server
  systemctl enable nfs-lock
  systemctl enable nfs-idmap
  systemctl start rpcbind
  systemctl start nfs-server
  systemctl start nfs-lock
  systemctl start nfs-idmap
  localip=`hostname -i | cut --delimiter='.' -f -3`
  echo "$IPPRE:/mnt/blk/share     /mnt/blk/share      nfs defaults,mountproto=tcp,sec=sys 0 0" | tee -a /etc/fstab
  mount -a
}

if [ $IP = $IPPRE ];
then
  echo Installing Server
  touch NFS_SERVER
  install_nfsserver
else
  echo Installing Client
  touch NFS_CLIENT
  install_nfsclient
fi
