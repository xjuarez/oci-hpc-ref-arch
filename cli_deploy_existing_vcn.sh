#!/bin/bash
#SET TENANCY
export USER=opc
export CNODES=2
export C=$1
export PRE=`uuidgen | cut -c-5`
export subnet=4
export IMAGE=Oracle-Linux-7.5-2018.05.09-1
export ad=1
export SIZE=BM.Standard1.36	
export BLKSIZE_TB=2
export region=us-ashburn-1

export VCNNAME=main
export SUBNETNAME="Public Subnet kWVD:US-ASHBURN-AD-1"
#export region=eu-frankfurt-1
#export region=us-phoenix-1
#export region=eu-london-1

export AD=`oci iam availability-domain list --profile $P -c $C --region $region | jq -r .data[].name | grep -e '-'$ad`
export OS=`oci compute image list -c $C --region $region --output table --query "data [*].{ImageName:\"display-name\", OCID:id}" | grep $IMAGE | awk '{ print $4 }'`
export INFO='--region '$region' --availability-domain '$AD' -c '$C

#CREATE NETWORK
echo
echo 'Finding Network'
V=`oci  network vcn list -c $C --region $region | jq -r '.data[] | select(."display-name" | contains ("$VCNNAME")) | .id'`
NG=`oci network internet-gateway list -c $C --region $region --vcn-id=$V | jq -r '.data[].id'`
RT=`oci network route-table list -c $C --region $region --vcn-id=$V | jq -r '.data[].id'`
SL=`oci network security-list list -c $C --region $region --vcn-id=$V | jq -r '.data[].id'`
S=`oci network subnet list -c $C --region $region --vcn-id=$V | jq -r '.data[] | select(."display-name" | contains ("AD-1")) | .id'`

#CREATE FILE SYSTEM
#echo
#echo 'Creating File System'
#FSS=`oci fs file-system create --region $region --availability-domain "$AD" -c $C --display-name "HPC_File_System" --wait-for-state ACTIVE | jq -r '.data.id'`
#MT=`oci fs mount-target create --region $region --availability-domain "$AD" -c $C --subnet-id $S --display-name "mountTarget$PRE" --wait-for-state ACTIVE --ip-address 10.0.0.20 | jq -r '.data.id'`

#CREATE BLOCK AND HEADNODE
echo
echo 'Creating Block Storage and Headnode'
BLKSIZE_GB=`expr $BLKSIZE_TB \* 1024`
BV=`oci bv volume create $INFO --display-name "hpc_block-$PRE" --size-in-gbs $BLKSIZE_GB --wait-for-state AVAILABLE | jq -r '.data.id'`
sleep 60
masterID=`oci compute instance launch $INFO --shape "$SIZE" --display-name "hpc_master-$PRE" --image-id $OS --subnet-id $S --private-ip 10.0.$subnet.2 --wait-for-state RUNNING --user-data-file scripts/bm_configure.sh --ssh-authorized-keys-file ~/.ssh/id_rsa.pub | jq -r '.data.id'`
attachID=`oci compute volume-attachment attach --region $region --instance-id $masterID --type iscsi --volume-id $BV --wait-for-state ATTACHED | jq -r '.data.id'`
attachIQN=`oci compute volume-attachment get --volume-attachment-id $attachID --region $region | jq -r .data.iqn`
attachIPV4=`oci compute volume-attachment get --volume-attachment-id $attachID --region $region | jq -r .data.ipv4`

#CREATE COMPUTE
echo
echo 'Creating Compute Nodes'
computeData=$(for i in `seq 1 $CNODES`; do oci compute instance launch $INFO --shape "$SIZE" --display-name "hpc_cn_$i-$PRE" --image-id $OS --subnet-id $S --assign-public-ip true  --user-data-file scripts/bm_configure.sh --ssh-authorized-keys-file ~/.ssh/id_rsa.pub; done)

#LIST IP's
echo
echo 'Created Headnode and Compute Nodes'
echo 'Waiting seven minutes for init scripts to complete'
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
ssh $USER@$masterIP 'while [ ! -f /var/log/CONFIG_COMPLETE ]; do sleep 60; echo "Waiting for node to complete configuration"; done'
echo

echo 'Attaching block volume to head node'
ssh -o StrictHostKeyChecking=no $USER@$masterIP sudo sh /root/oci-hpc-ref-arch/scripts/mount_block.sh $attachIQN $attachIPV4
echo

echo 'Creating NFS share'
sleep 60
ssh -o StrictHostKeyChecking=no $USER@$masterIP pdsh -w ^/home/$USER/hostfile sudo sh /root/oci-hpc-ref-arch/scripts/nfs_setup.sh $masterPRVIP

echo 'Installing Ganglia'
sleep 60
ssh -o StrictHostKeyChecking=no $USER@$masterIP pdsh -w ^/home/$USER/hostfile sudo sh /root/oci-hpc-ref-arch/scripts/ganglia_setup.sh hpc_master-$PRE


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
echo Complete
EOF

chmod +x removeCluster-$PRE.sh
