#!/bin/bash

source $(dirname $(realpath $0))/vm1.config

echo $EXTERNAL_IF
echo $INTERNAL_IF
echo $MANAGEMENT_IF
echo $VLAN
echo $EXT_IP # или External_IP=172.16.1.1/24
echo $EXT_GW
echo $INT_IP
echo $VLAN_IP
echo $NGINX_PORT
echo $APACHE_VLAN_IP

if [ $EXT_IP = "DHCP" ]
then
ip addr flus dev $EXTERNAL_IF
ip route del default 2>/dev/null
dhclient -4 -q $EXTERNAL_IF
else 
ip addr flus dev $EXTERNAL_IF
ip addr add $EXT_IP dev $EXTERNAL_IF broadcast +
ip route del default 2>/dev/null
ip link set $EXTERNAL_IF up
ip route add default via $EXT_GW
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
fi

ip addr flus dev $INTERNAL_IF
ip addr add $INT_IP dev $INTERNAL_IF broadcast +
ip link set $INTERNAL_IF up

#apt-get update
#apt-get -y install vlan

modprobe 8021q
vconfig add $INTERNAL_IF $VLAN
ip addr add $VLAN_IP dev $INTERNAL_IF.$VLAN broadcast +
ip link set $INTERNAL_IF.$VLAN up


# Включаем форвардинг пакетов
echo 1 > /proc/sys/net/ipv4/ip_forward

# Разрешаем трафик на loopback-интерфейсе
iptables -A INPUT -i lo -j ACCEPT

# Разрешаем доступ из внутренней сети наружу
iptables -A FORWARD -i $INTERNAL_IF -o $EXTERNAL_IF -j ACCEPT

# Включаем NAT 
iptables -t nat -A POSTROUTING -o $EXTERNAL_IF -s $INT_IP -j MASQUERADE 

# Разрешаем ответы из внешней сети
iptables -A FORWARD -i $EXTERNAL_IF -m state --state ESTABLISHED,RELATED -j ACCEPT

# Запрещаем доступ снаружи во внутреннюю сеть
iptables -A FORWARD -i $EXTERNAL_IF -o $INTERNAL_IF -j REJECT

NGINX_EXT_IP=$(ip -4 addr show ${EXTERNAL_IF} |grep inet |awk '{print $2}' |sed 's!/.*!!')

openssl req -x509 -newkey rsa:4096 -keyout /etc/ssl/certs/root-ca.key -nodes -out /etc/ssl/certs/root-ca.crt -subj "/CN=VDV/L=Kharkov/C=UA"

openssl rsa -in /etc/ssl/certs/root-ca.key -out /etc/ssl/certs/root-ca.key

openssl genrsa -out /etc/ssl/certs/web.key 4096

openssl req -new -sha256 -key /etc/ssl/certs/web.key -subj "/C=UA/L=Kharkiv/O=Volkov, Inc./CN=$HOSTNAME" -reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nbasicConstraints=CA:FALSE\nsubjectAltName=DNS:$HOSTNAME,IP:$NGINX_EXT_IP")) -out /etc/ssl/certs/web.csr


openssl x509 -req -days 365  -CA /etc/ssl/certs/root-ca.crt -CAkey /etc/ssl/certs/root-ca.key -set_serial 01 -extensions SAN -extfile <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nbasicConstraints=CA:FALSE\nsubjectAltName=DNS:$HOSTNAME,IP:$NGINX_EXT_IP")) -in /etc/ssl/certs/web.csr -out /etc/ssl/certs/web.crt

cat /etc/ssl/certs/root-ca.crt >> /etc/ssl/certs/web.crt

apt-get update
apt-get -y install nginx

echo "
server {
listen      $NGINX_EXT_IP:$NGINX_PORT ssl;
#       server_name  vm1;
ssl_certificate      /etc/ssl/certs/web.crt;
ssl_certificate_key  /etc/ssl/certs/web.key;
#    ssl_protocols SSLv3 TLSv1 TLSv1.1 TLSv1.2;
#    ssl_ciphers  "RC4:HIGH:!aNULL:!MD5:!kEDH";
location / {
proxy_pass http://$APACHE_VLAN_IP/;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header Upgrade \$http_upgrade;
}
}" > /etc/nginx/conf.d/ssh_termination_proxy.conf 

rm /etc/nginx/sites-enabled/default

systemctl restart nginx

