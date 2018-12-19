#!/bin/bash
MYUSER=opc
SUB=`hostname -i | awk -F'.' '{ print $3 }'`
MYHOST=10.0.$SUB.2

sudo systemctl stop firewalld
sudo systemctl disable firewalld

wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
rpm -ivh epel-release-latest-7.noarch.rpm

yum repolist
yum check-update
yum install -y -q pdsh stress axel openmpi screen go
yum install -y -q nfs-utils sshpass nmap htop screen git psmisc axel
yum install -y -q gcc libffi-devel python-devel openssl-devel mysql
#yum install -y -q  fontconfig freetype freetype-devel fontconfig-devel libstdc++ libXext libXt libXrender-devel.x86_64 libXrender.x86_64 mesa-libGL.x86_64
#yum group install -y -q "X Window System"
yum group install -y -q "Development Tools"

IP=`hostname -i`
localip=`echo $IP | cut --delimiter='.' -f -3`
myhost=`hostname`
nmap -p 80 $localip.0/20 | grep $localip | awk '{ print $5 }'> /home/$MYUSER/hostfile
sed '/10.0.'$SUB'.1/d' /home/$MYUSER/hostfile -i

cat << EOF >> /etc/security/limits.conf
*               hard    memlock         unlimited
*               soft    memlock         unlimited
*               hard    nofile          65535
*               soft    nofile          65535
EOF

#DISABLE HYPERTHREADING, INSTALL GANGLIA
cd ~
git clone https://github.com/oci-hpc/oci-hpc-ref-arch
#git clone https://github.com/oci-hpc/oci-hpc-benchmark
source oci-hpc-ref-arch/scripts/disable_ht.sh 0
#source oci-hpc-benchmark/get_files.sh
#source oci-hpc-ref-arch/scripts/nfs_setup.sh $MYHOST

#USER CONFIGURATION
mkdir -p /home/$MYUSER/bin

cat << EOF >> /home/$MYUSER/.bashrc
export WCOLL=/home/$MYUSER/hostfile
export PATH=/opt/intel/compilers_and_libraries_2018.1.163/linux/mpi/intel64/bin:\$PATH
export I_MPI_ROOT=/opt/intel/compilers_and_libraries_2018.1.163/linux/mpi
export MPI_ROOT=/opt/intel/compilers_and_libraries_2018.1.163/linux/mpi
export I_MPI_FABRICS=tcp
EOF

export WCOLL=/home/$MYUSER/hostfile

cat << EOF > /home/$MYUSER/.ssh/config
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    PasswordAuthentication no
    LogLevel QUIET
EOF
cat /home/$MYUSER/.ssh/id_rsa.pub >> /home/$MYUSER/.ssh/authorized_keys
chmod 644 /home/$MYUSER/.ssh/config

# Don't require password for HPC user sudo
echo "$MYUSER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
# Disable tty requirement for sudo
sed -i 's/^Defaults[ ]*requiretty/# Defaults requiretty/g' /etc/sudoers

chown $MYUSER:$MYUSER /home/$MYUSER/.ssh/*
chown $MYUSER:$MYUSER /home/$MYUSER/bin
chown $MYUSER:$MYUSER /home/$MYUSER/.bashrc

runuser -l $MYUSER -c "pdsh -w ^/home/$MYUSER/hostfile hostname > /home/$MYUSER/hostnames"
cat /home/$MYUSER/hostnames >> /etc/hosts
sed -i 's/: / /g' /etc/hosts
runuser -l $MYUSER -c "pdcp -w ^/home/$MYUSER/hostfile /etc/hosts ~"
runuser -l $MYUSER -c "pdsh -w ^/home/$MYUSER/hostfile sudo mv ~/hosts /etc/hosts"

'''
if [[ `hostname` = *master* ]];
then
    wget https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana-5.2.4-1.x86_64.rpm
    yum -y localinstall grafana-5.2.4-1.x86_64.rpm
    yum install -y python-rrdtool rrdtool
    grafana-cli plugins install grafana-simple-json-datasource
    service grafana-server restart
    ln -s /usr/lib64/librrd.so.4 /usr/lib64/librrd.so.8

    mkdir /home/$MYUSER/rrd_server
    cd /home/$MYUSER/rrd_server
    wget https://github.com/doublemarket/grafana-rrd-server/releases/download/v0.0.5/grafana-rrd-server_linux_amd64.gz
    gunzip grafana-rrd-server_linux_amd64.gz
    chmod +x grafana-rrd-server_linux_amd64
    echo export PATH=\$PATH:/home/$MYUSER/rrd_server >> /home/$MYUSER/.bashrc
    /home/$MYUSER/rrd_server/grafana-rrd-server_linux_amd64 -r /var/lib/ganglia/rrds/oci/__SummaryInfo__ > output.txt 2>&1 </dev/null &
    service grafana-server restart &
    /sbin/chkconfig --add grafana-server &
    
    cat <<EOF | sudo tee /etc/yum.repos.d/influxdb.repo
[influxdb]
name = InfluxDB Repository - RHEL \$releasever
baseurl = https://repos.influxdata.com/rhel/\$releasever/\$basearch/stable
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdb.key
EOF
sudo yum install -y influxdb
sudo systemctl start influxdb
influxd -config /etc/influxdb/influxdb.conf &
fi
'''

touch /var/log/CONFIG_COMPLETE
