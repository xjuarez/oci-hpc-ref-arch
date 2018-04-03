#!/bin/bash
IPPRE=10.0.0.2
IP=`hostname -i`

install_nfsserver()
{
  #Setup the NFS server
  localip=`echo $IP | cut --delimiter='.' -f -3`
  mkdir -p /mnt/share/scratch
  echo "/mnt/share/scratch 10.0.0.0/20(rw,sync,no_root_squash,no_all_squash)" | tee -a /etc/exports
  systemctl enable rpcbind
  systemctl enable nfs-server
  systemctl enable nfs-lock
  systemctl enable nfs-idmap
  systemctl start rpcbind
  systemctl start nfs-server
  systemctl start nfs-lock
  systemctl start nfs-idmap
  systemctl restart nfs-server
  chmod 777 /mnt/share/scratch
}

install_nfsclient()
{
  sleep 120
  mkdir -p /mnt/share/scratch
  systemctl enable rpcbind
  systemctl enable nfs-server
  systemctl enable nfs-lock
  systemctl enable nfs-idmap
  systemctl start rpcbind
  systemctl start nfs-server
  systemctl start nfs-lock
  systemctl start nfs-idmap
  localip=`hostname -i | cut --delimiter='.' -f -3`
  echo "$IPPRE:/mnt/share/scratch     /mnt/share/scratch      nfs defaults,mountproto=tcp,sec=sys 0 0" | tee -a /etc/fstab
  #echo "$IPPRE:/home     /home      nfs defaults,mountproto=tcp,sec=sys 0 0" | tee -a /etc/fstab
  mount -a
  chmod 777 /mnt/share/scratch
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
