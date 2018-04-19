#!/bin/bash

source $(dirname $(realpath $0))/vm2.config

echo $INTERNAL_IF
echo $MANAGEMENT_IF
echo $VLAN
echo $APACHE_VLAN_IP
echo $INT_IP
echo $GW_IP

ip addr flus dev $INTERNAL_IF
ip addr add $INT_IP dev $INTERNAL_IF broadcast +
ip link set $INTERNAL_IF up
ip route add default via $GW_IP
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

modprobe 8021q
vconfig add $INTERNAL_IF $VLAN
ip addr add $APACHE_VLAN_IP dev $INTERNAL_IF.$VLAN broadcast +
ip link set $INTERNAL_IF.$VLAN up

apt-get update
apt-get -y install apache2

sed -i '/Listen\ 80/d' /etc/apache2/ports.conf
AP=$(echo $APACHE_VLAN_IP |sed 's!/.*!!')
echo "Listen $AP:80 " >> /etc/apache2/ports.conf
systemctl restart apache2
