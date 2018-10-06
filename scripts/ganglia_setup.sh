#!/bin/bash
set +e


if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

if [ $# != 1 ]; then
    echo "Usage: $0 <ManagementHost>"
    exit 1
fi

MGMT_HOSTNAME=$1
CLUSTER_NAME=oci
CLUSTER_PORT=8649

# CHECKS FOR HEADNODE
is_master()
{
    hostname | grep "$MGMT_HOSTNAME"
    return $?
}

install_ganglia_gmetad()
{
	echo "Installing Ganglia Server"
	yum -y -q install epel-release
	yum -y -q install httpd php php-mysql php-gd php-ldap php-odbc php-pear php-xml php-xmlrpc php-mbstring php-snmp php-soap curl mesa-libEGL mesa-libGL
	yum -y -q install rrdtool rrdtool-devel ganglia-web ganglia-metad ganglia-gmond ganglia-gmond-python httpd apr-devel zlib-devel libconfuse-devel expat-devel pcre-devel

	#SETUP SERVER	
	GMETAD_CONFIG=/etc/ganglia/gmetad.conf	
	sed -i 's/^data_source.*/data_source "'$MGMT_HOSTNAME' cluster" '$MGMT_HOSTNAME'/g' $GMETAD_CONFIG
	sed -i 's/# gridname "MyGrid".*/gridname "OCI"/g' $GMETAD_CONFIG
	sed -i 's/# setuid off.*/setuid off/g' $GMETAD_CONFIG
	sed -i 's/setuid_username ganglia.*/#setuid_username ganglia/g' $GMETAD_CONFIG

	#configure Ganglia web server
	sed -i '0,/Require local/{s/Require local/Require all granted/}' /etc/httpd/conf.d/ganglia.conf
	chown root:root -R /var/lib/ganglia/rrds/
	systemctl restart httpd
	systemctl restart gmetad
	systemctl enable httpd
	systemctl enable gmetad	

}

install_gmond()
{
	echo "Installing Ganglia Client"

	yum -y -q install epel-release	
	yum -y -q install ganglia-gmond

	#configure Ganglia monitoring
	GMOND_CONFIG=/etc/ganglia/gmond.conf	
	sed -i '0,/name = "unspecified"/{s/name = "unspecified"/name = "'$CLUSTER_NAME'"/}'  $GMOND_CONFIG 
	sed -i '0,/mcast_join = 239.2.11.71/{s/mcast_join = 239.2.11.71/host = '$MGMT_HOSTNAME'/}'  $GMOND_CONFIG
	sed -i '0,/mcast_join = 239.2.11.71/{s/mcast_join = 239.2.11.71//}'  $GMOND_CONFIG
	sed -i '0,/bind = 239.2.11.71/{s/bind = 239.2.11.71//}'  $GMOND_CONFIG
	sed -i '0,/retry_bind = true/{s/retry_bind = true//}'  $GMOND_CONFIG
	sed -i '0,/send_metadata_interval = 0/{s/send_metadata_interval = 0/send_metadata_interval = 60/}'  $GMOND_CONFIG
	sed -i '0,/port = 8649/{s/port = 8649/port = '$CLUSTER_PORT'/}'  $GMOND_CONFIG
	sed -i '0,/port = 8649/{s/port = 8649/port = '$CLUSTER_PORT'/}'  $GMOND_CONFIG
	sed -i '0,/port = 8649/{s/port = 8649/port = '$CLUSTER_PORT'/}'  $GMOND_CONFIG
	sed -i 's/#bind_hostname = yes.*/bind_hostname = yes/g' $GMOND_CONFIG

	systemctl restart gmond
	systemctl enable gmond
}

SETUP_MARKER=/var/tmp/install_ganglia.marker
if [ -e "$SETUP_MARKER" ]; then
    echo "We're already configured, exiting..."
    exit 0
fi

# Disable security
sed -i 's/SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
setenforce 0
systemctl stop firewalld
systemctl disable firewalld

if is_master; then
	install_ganglia_gmetad
fi

install_gmond

# Create marker file so we know we're configured
touch $SETUP_MARKER

