#!/bin/bash

echo "Please enter your domain name:"
read domain_name

echo "Please enter your password:"
read password

echo "DomainName: $domain_name"
echo "Password: $password"

set -x
apt update
apt upgrade
echo ----------Trojan----------
cd /root
mkdir trojan
cd trojan
wget https://github.com/p4gefau1t/trojan-go/releases/download/v0.10.6/trojan-go-linux-amd64.zip
apt install unzip
unzip trojan-go-linux-amd64.zip
curl https://get.acme.sh | sh
apt install socat
ln -s /root/.acme.sh/acme.sh /usr/local/bin/acme.sh
acme.sh --register-account -m your_email@gmail.com
acme.sh --issue -d $domain_name --standalone -k ec-256
acme.sh --installcert -d $domain_name --ecc --key-file /root/trojan/server.key --fullchain-file /root/trojan/server.crt
touch config.json
echo '{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 10000,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": ["$password"],
  "ssl": {
    "cert": "server.crt",
    "key": "server.key",
    "sni": "$domain_name"
  }
}' > config.json
apt install nginx
nohup ./trojan-go > trojan.log 2>&1 &
iptables -t nat -A PREROUTING -p tcp --dport 10000:11000 -j REDIRECT --to-port 10000
iptables -t nat -A PREROUTING -p udp --dport 10000:11000 -j REDIRECT --to-port 10000
echo ----------Aria----------
apt install aria2
mkdir /root/.aria2
touch /root/.aria2/aria2.session
touch /root/.aria2/aria2.conf
echo '
dir=/home/download
input-file=/root/.aria2/aria2.session
save-session=/root/.aria2/aria2.session
log=/root/.aria2/aria2.log
continue=true
enable-rpc=true
rpc-secret=$password
rpc-listen-port=6800
rpc-allow-origin-all=true
rpc-listen-all=true
#rpc-secure=true
#rpc-certificate=/root/trojan/server.cer
#rpc-private-key=/root/trojan/server.key
' > /root/.aria2/aria2.conf
aria2c --daemon=true --conf-path=/root/.aria2/aria2.conf
echo ----------Filebrowser----------
cd /root
mkdir filebrowser
cd filebrowser
wget https://github.com/filebrowser/filebrowser/releases/download/v2.23.0/linux-amd64-filebrowser.tar.gz
tar -zxvf linux-amd64-filebrowser.tar.gz
./filebrowser config init
./filebrowser config set --address 0.0.0.0 --baseurl '/f' --port 10001 --log ./filebrowser.log --root /home/download
./filebrowser users add admin $password --perm.admin
nohup ./filebrowser > /dev/null 2>&1 &
echo ----------Nginx----------
cd /var/www/html
mkdir a
cd a
wget https://github.com/mayswind/AriaNg/releases/download/1.3.3/AriaNg-1.3.3.zip
unzip AriaNg-1.3.3.zip
echo '
server {
	listen 443 ssl;
	server_name $domain_name;
	ssl_certificate /root/trojan/server.crt;
	ssl_certificate_key /root/trojan/server.key;
	root /var/www/html;
	location / {
		try_files $uri $uri/ =404;
	}
	location /a {
		try_files $uri $uri/ =404;
	}
	location /f {
		proxy_pass http://127.0.0.1:10001;
		proxy_set_header Host $host;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header X-Real-Ip $remote_addr;
	}
}
server {
	listen 80;
	server_name $domain_name;
	location / {
		rewrite ^(.*)$ https://$host$1 permanent;
	}
 	location /a {
  		root /var/www/html;
		try_files $uri $uri/ =404;
	}
}
' > /etc/nginx/sites-enabled/default
nginx -t
systemctl start nginx
systemctl reload nginx
