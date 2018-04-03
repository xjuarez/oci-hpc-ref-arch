#!/bin/bash
#SET TENANCY
export CNODES=4
export C=$1
export PRE=`uuidgen | cut -c-5`
export region=us-ashburn-1
#export region=eu-frankfurt-1
export AD=kWVD:US-ASHBURN-AD-1
#export AD=kWVD:EU-FRANKFURT-1-AD-3
#export OS=ocid1.image.oc1.phx.aaaaaaaav4gjc4l232wx5g5drypbuiu375lemgdgnc7zg2wrdfmmtbtyrc5q #OracleLinux, PHX
export OS=ocid1.image.oc1.iad.aaaaaaaautkmgjebjmwym5i6lvlpqfzlzagvg5szedggdrbp6rcjcso3e4kq #OracleLinux, IAD
#export OS=ocid1.image.oc1.eu-frankfurt-1.aaaaaaaamueig267buvha27g2zr7hqthtix55dnsc3yizwj62yxxjg4lwtka #OracleLinux, FRA
#wget https://raw.githubusercontent.com/tanewill/oci_hpc/master/bm_configure.sh

#LIST OS OCID's
#oci compute image list -c $C --output table --region $region --query "data [*].{ImageName:\"display-name\", OCID:id}"

#CREATE NETWORK
echo
echo 'Creating Network'
V=`oci network vcn create --region $region --cidr-block 10.0.0.0/24 --compartment-id $C --display-name "hpc_vcn-$PRE" --wait-for-state AVAILABLE | jq -r '.data.id'`
NG=`oci network internet-gateway create --region $region -c $C --vcn-id $V --is-enabled TRUE --display-name "hpc_ng-$PRE" --wait-for-state AVAILABLE | jq -r '.data.id'`
RT=`oci network route-table create --region $region -c $C --vcn-id $V --display-name "hpc_rt-$PRE" --wait-for-state AVAILABLE --route-rules '[{"cidrBlock":"0.0.0.0/0","networkEntityId":"'$NG'"}]' | jq -r '.data.id'`
SL=`oci network security-list create --region $region -c $C --vcn-id $V --display-name "hpc_sl-$PRE" --wait-for-state AVAILABLE --egress-security-rules '[{"destination":  "0.0.0.0/0",  "protocol": "all", "isStateless":  null}]' --ingress-security-rules '[{"source":  "0.0.0.0/0",  "protocol": "all", "isStateless":  null}]' | jq -r '.data.id'`
S=`oci network subnet create -c $C --vcn-id $V --region $region --availability-domain "$AD" --display-name "hpc_subnet-$PRE" --cidr-block "10.0.0.0/26" --route-table-id $RT --security-list-ids '["'$SL'"]' --wait-for-state AVAILABLE | jq -r '.data.id'`

#CREATE FILE SYSTEM
echo
echo 'Creating File System'
FSS=`oci fs file-system create --region $region --availability-domain "$AD" -c $C --display-name "HPC_File_System" --wait-for-state ACTIVE | jq -r '.data.id'`
MT=`oci fs mount-target create --region $region --availability-domain "$AD" -c $C --subnet-id $S --display-name "mountTarget$PRE" --wait-for-state ACTIVE --ip-address 10.0.0.20 | jq -r '.data.id'`

#CREATE HEADNODE
echo
echo 'Creating Headnode'
masterID=`oci compute instance launch --region $region --availability-domain "$AD" -c $C --shape "BM.DenseIO2.52" --display-name "hpc_master-$PRE" --image-id $OS --subnet-id $S --private-ip 10.0.0.2 --wait-for-state RUNNING --user-data-file hn_configure.sh --ssh-authorized-keys-file ~/.ssh/id_rsa.pub | jq -r '.data.id'`

#CREATE COMPUTE
echo
echo 'Creating Compute Nodes'
computeData=$(for i in `seq 1 $CNODES`; do oci compute instance launch --region $region --availability-domain "$AD" -c $C --shape "BM.Standard2.52" --display-name "hpc_cn$i-$PRE" --image-id $OS --subnet-id $S --assign-public-ip true  --user-data-file hn_configure.sh --ssh-authorized-keys-file ~/.ssh/id_rsa.pub; done)

#--skip-source-dest-check true 

#LIST IP's
echo
echo 'Created Headnode and Compute Nodes'
echo 'Waiting five minutes for IP addresses'
sleep 300

masterIP=$(oci compute instance list-vnics --region $region --instance-id $masterID | jq -r '.data[]."public-ip"')

for iid in `oci compute instance list --region $region -c $C | jq -r '.data[] | select(."lifecycle-state"=="RUNNING") | .id'`; do newip=`oci compute instance list-vnics --region $region --instance-id $iid | jq -r '.data[0] | ."display-name"+": "+."private-ip"+", "+."public-ip"'`; echo $iid, $newip; done

scp -o StrictHostKeyChecking=no ~/.ssh/id_rsa opc@$masterIP:~/.ssh/

#CREATE REMOVE SCRIPT
cat << EOF >> removeCluster-$PRE.sh
#!/bin/bash
export masterIP=$masterIP
export C=$1
export PRE=$PRE
export region=$region
export AD=$AD
export V=$V
export NG=$NG
export RT=$RT
export SL=$SL
export S=$S
export masterID=$masterID


#DELETE INSTANCES
echo Removing: Head Node
oci compute instance terminate --region $region --instance-id $masterID --force

EOF
cat << "EOF" >> removeCluster-$PRE.sh
echo Removing: Compute Nodes
for instanceid in $(oci compute instance list --region $region -c $C | jq -r '.data[] | select(."display-name" | contains ("'$PRE'")) | .id'); do oci compute instance terminate --region $region --instance-id $instanceid --force; done
sleep 30
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
EOF

chmod +x removeCluster-$PRE.sh