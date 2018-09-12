#!/bin/bash
#SET TENANCY
export USER=opc
export CNODES=1
export C=$1
export PRE=`uuidgen | cut -c-5`
export subnet=9
export IMAGE=Oracle-Linux-7.5-2018.08.14-0
export ad=3
export SIZE=BM.Standard2.52
export BLKSIZE_TB=1
#export region=us-ashburn-1
export region=eu-frankfurt-1
#export region=us-phoenix-1
#export region=eu-london-1

export AD=`oci iam availability-domain list -c $C --region $region --output table | grep 'AD-'$ad | awk '{ print $4 }'`
export OS=`oci compute image list -c $C --region $region --output table --query "data [*].{ImageName:\"display-name\", OCID:id}" | grep $IMAGE | awk '{ print $4 }'`
export INFO='--region '$region' --availability-domain '$AD' -c '$C

#CREATE NETWORK
echo
STARTTIME=`date +%T' '%D`
echo 'Deploying HPC Cluster: '$PRE
echo 'Creating Network: '`date +%T' '%D`
V=`oci network vcn create --region $region --cidr-block 10.0.$subnet.0/24 --compartment-id $C --display-name "hpc_vcn-$PRE" --wait-for-state AVAILABLE | jq -r '.data.id'`
NG=`oci network internet-gateway create --region $region -c $C --vcn-id $V --is-enabled TRUE --display-name "hpc_ng-$PRE" --wait-for-state AVAILABLE | jq -r '.data.id'`
RT=`oci network route-table create --region $region -c $C --vcn-id $V --display-name "hpc_rt-$PRE" --wait-for-state AVAILABLE --route-rules '[{"cidrBlock":"0.0.0.0/0","networkEntityId":"'$NG'"}]' | jq -r '.data.id'`
SL=`oci network security-list create --region $region -c $C --vcn-id $V --display-name "hpc_sl-$PRE" --wait-for-state AVAILABLE --egress-security-rules '[{"destination":  "0.0.0.0/0",  "protocol": "all", "isStateless":  null}]' --ingress-security-rules '[{"source":  "0.0.0.0/0",  "protocol": "all", "isStateless":  null}]' | jq -r '.data.id'`
S=`oci network subnet create -c $C --vcn-id $V --region $region --availability-domain "$AD" --display-name "hpc_subnet-$PRE" --cidr-block "10.0.$subnet.0/26" --route-table-id $RT --security-list-ids '["'$SL'"]' --wait-for-state AVAILABLE | jq -r '.data.id'`

#CREATE FILE SYSTEM
#echo
#echo 'Creating File System'
#FSS=`oci fs file-system create --region $region --availability-domain "$AD" -c $C --display-name "HPC_File_System" --wait-for-state ACTIVE | jq -r '.data.id'`
#MT=`oci fs mount-target create --region $region --availability-domain "$AD" -c $C --subnet-id $S --display-name "mountTarget$g" --wait-for-state ACTIVE --ip-address 10.0.0.20 | jq -r '.data.id'`

#CREATE BLOCK AND HEADNODE
echo
echo 'Creating Block Storage and Headnode: '`date +%T' '%D`
BLKSIZE_GB=`expr $BLKSIZE_TB \* 1024`
BV=`oci bv volume create $INFO --display-name "hpc_block-$PRE" --size-in-gbs $BLKSIZE_GB --wait-for-state AVAILABLE | jq -r '.data.id'`
masterID=`oci compute instance launch $INFO --shape "$SIZE" --display-name "hpc_"$PRE"_master" --image-id $OS --subnet-id $S --private-ip 10.0.$subnet.2 --wait-for-state RUNNING --user-data-file scripts/bm_configure.sh --ssh-authorized-keys-file ~/.ssh/id_rsa.pub | jq -r '.data.id'`
attachID=`oci compute volume-attachment attach --region $region --instance-id $masterID --type iscsi --volume-id $BV --wait-for-state ATTACHED | jq -r '.data.id'`
attachIQN=`oci compute volume-attachment get --volume-attachment-id $attachID --region $region | jq -r .data.iqn`
attachIPV4=`oci compute volume-attachment get --volume-attachment-id $attachID --region $region | jq -r .data.ipv4`

#CREATE COMPUTE
echo
echo 'Creating Compute Nodes: '`date +%T' '%D`
computeData=$(for i in `seq 1 $CNODES`; do oci compute instance launch $INFO --shape "$SIZE" --display-name "hpc_"$PRE"_cn$i" --image-id $OS --subnet-id $S --assign-public-ip true  --user-data-file scripts/bm_configure.sh --ssh-authorized-keys-file ~/.ssh/id_rsa.pub; done)

#LIST IP's
echo
echo 'Created Headnode and Compute Nodes'
echo 'Waiting seven minutes for init scripts to complete from: '`date +%T' '%D`
sleep 420

masterIP=$(oci compute instance list-vnics --region $region --instance-id $masterID | jq -r '.data[]."public-ip"')
masterPRVIP=$(oci compute instance list-vnics --region $region --instance-id $masterID | jq -r '.data[]."private-ip"')
#for iid in `oci compute instance list --region $region -c $C | jq -r '.data[] | select(."lifecycle-state"=="RUNNING") | .id'`; do newip=`oci compute instance list-vnics --region $region --instance-id $iid | jq -r '.data[0] | ."display-name"+": "+."private-ip"+", "+."public-ip"'`; echo $iid, $newip; done

#COMMANDS TO RUN ON MASTER
echo
echo 'Adding key to head node'
n=0
until [ $n -ge 5 ]
do
  scp -o StrictHostKeyChecking=no ~/.ssh/id_rsa $USER@$masterIP:~/.ssh/ && break  
  n=$[$n+1]
  sleep 60
done

echo 'Waiting for node to complete configuration'
ssh $USER@$masterIP 'while [ ! -f /var/log/CONFIG_COMPLETE ]; do sleep 60; echo "Waiting for node to complete configuration: `date +%T`"; done'
echo

echo 'Attaching block volume to head node: '`date +%T' '%D`
ssh -o StrictHostKeyChecking=no $USER@$masterIP sudo sh /root/oci-hpc-ref-arch/scripts/mount_block.sh $attachIQN $attachIPV4
echo

echo 'Creating NFS share: '`date +%T' '%D`
sleep 60
ssh -o StrictHostKeyChecking=no $USER@$masterIP pdsh -w ^/home/$USER/hostfile sudo sh /root/oci-hpc-ref-arch/scripts/nfs_setup.sh $masterPRVIP

echo 'Installing Ganglia: '`date +%T' '%D`
sleep 60
ssh -o StrictHostKeyChecking=no $USER@$masterIP pdsh -w ^/home/$USER/hostfile sudo sh /root/oci-hpc-ref-arch/scripts/ganglia_setup.sh hpc_$PRE"_master"
ssh -o StrictHostKeyChecking=no $USER@$masterIP 'go get github.com/yudai/gotty && screen -S test -d -m go/bin/gotty -c opc:+ocihpc123456 -w bash'

echo 'Transfer OpenFOAM: '`date +%T' '%D`
sleep 60
scp -o StrictHostKeyChecking=no install_openfoam.sh $USER@$masterIP: && break
ssh -o StrictHostKeyChecking=no $USER@$masterIP 'chmod +x install_openfoam.sh && ./install_openfoam.sh'

echo
echo 'HPC Cluster: '$PRE
echo 'External IP Address: '$masterIP
echo 'Started deployment: '$STARTTIME
echo 'Completed deployment: '`date +%T' '%D`
echo
echo 'Ganglia installed, navigate to http://'$masterIP'/ganglia on a web browser'
echo 'Grafana installed, navigate to http://'$masterIP':3000 on a web browser'
echo 'GOTTY installed, navigate to http://'$masterIP':8080 on a web browser'
echo 'ssh '$USER'@'$masterIP


#CREATE REMOVE SCRIPT
cat << EOF >> removeCluster-$PRE.sh
#!/bin/bash
export masterIP=$masterIP
export masterPRVIP=$masterPRVIP
export USER=$USER
export C=$1
export PRE=$PRE
export region=$region
export AD=$AD
export V=$V
export NG=$NG
export RT=$RT
export SL=$SL
export S=$S
export BV=$BV
export masterID=$masterID


#DELETE INSTANCES
echo Removing: Head Node
oci compute instance terminate --region $region --instance-id $masterID --force

EOF
cat << "EOF" >> removeCluster-$PRE.sh
echo Removing: Compute Nodes
for instanceid in $(oci compute instance list --region $region -c $C | jq -r '.data[] | select(."display-name" | contains ("'$PRE'")) | .id'); do oci compute instance terminate --region $region --instance-id $instanceid --force; done
sleep 60
echo Removing: Subnet, Route Table, Security List, Gateway, and VCN
oci network subnet delete --region $region --subnet-id $S --force
sleep 10
oci network route-table delete --region $region --rt-id $RT --force
sleep 10
oci network security-list delete --region $region --security-list-id $SL --force
sleep 10
oci network internet-gateway delete --region $region --ig-id $NG --force
sleep 10
oci network vcn delete --region $region --vcn-id $V --force
echo Complete
mv removeCluster-$PRE.sh .removeCluster-$PRE.sh
EOF

chmod +x removeCluster-$PRE*.sh
