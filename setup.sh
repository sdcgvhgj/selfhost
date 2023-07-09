#!/bin/bash

echo "password:"
read password
echo "your password is: $password"

set -x
apt update -y
# apt upgrade -y

echo ----------Trojan----------
cd /root
mkdir trojan
cd trojan
wget https://github.com/p4gefau1t/trojan-go/releases/download/v0.10.6/trojan-go-linux-amd64.zip
apt install -y unzip
unzip trojan-go-linux-amd64.zip
curl https://get.acme.sh | sh
apt install -y socat 
ln -s /root/.acme.sh/acme.sh /usr/local/bin/acme.sh
acme.sh --register-account -m sdcgvhgj@qq.com
acme.sh --issue -d sdcgvhgj.top --standalone -k ec-256
acme.sh --installcert -d sdcgvhgj.top --ecc --key-file /root/trojan/server.key --fullchain-file /root/trojan/server.crt
echo "
run-type: server
local-addr: 0.0.0.0
local-port: 10000
remote-addr: 127.0.0.1
remote-port: 80
password:
  - $password
ssl:
  cert: server.crt
  key: server.key
  sni: sdcgvhgj.top
" > config.yaml
nohup ./trojan-go > trojan.log 2>&1 &
iptables -t nat -A PREROUTING -p tcp --dport 10000:12000 -j REDIRECT --to-port 10000
iptables -t nat -A PREROUTING -p udp --dport 10000:12000 -j REDIRECT --to-port 10000

echo ----------Aria----------
apt install -y aria2
mkdir /root/.aria2
touch /root/.aria2/aria2.session
touch /root/.aria2/aria2.conf
mkdir /home/download
echo "
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
" > /root/.aria2/aria2.conf
aria2c --daemon=true --conf-path=/root/.aria2/aria2.conf

echo ----------Filebrowser----------
cd /root
mkdir filebrowser
cd filebrowser
wget https://github.com/filebrowser/filebrowser/releases/download/v2.23.0/linux-amd64-filebrowser.tar.gz
tar -zxvf linux-amd64-filebrowser.tar.gz
./filebrowser config init
./filebrowser config set --address 0.0.0.0 --baseurl '/f' --port 10001 --log ./filebrowser.log --root /home
./filebrowser users add admin $password --perm.admin
nohup ./filebrowser > /dev/null 2>&1 &

echo ----------Docker----------
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove $pkg; done
apt update
apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo ----------Nginx----------
apt install -y nginx
cd /var/www/html
mkdir a
cd a
wget https://github.com/mayswind/AriaNg/releases/download/1.3.3/AriaNg-1.3.3.zip
unzip AriaNg-1.3.3.zip
mkdir /home/files
echo '
server {
	listen 443 ssl;
	server_name sdcgvhgj.top;
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
	location /files {
		autoindex on;
		root /home;
	}
}
server {
	listen 80;
	root /var/www/html;
	server_name sdcgvhgj.top;
	location / {
		rewrite ^(.*)$ https://$host$1 permanent;
	}
	location /a {
		try_files $uri $uri/ =404;
	}
}
' > /etc/nginx/sites-enabled/default
nginx -t
systemctl start nginx
systemctl reload nginx

echo ----------NextCloud----------
systemctl stop nginx
acme.sh --issue -d cloud.sdcgvhgj.top --standalone -k ec-256
acme.sh --installcert -d cloud.sdcgvhgj.top --ecc --key-file /root/trojan/cloud.key --fullchain-file /root/trojan/cloud.crt
docker run \
-d \
--sig-proxy=false \
--name nextcloud-aio-mastercontainer \
--restart always \
--publish 20001:8080 \
--env APACHE_PORT=10002 \
--env APACHE_IP_BINDING=0.0.0.0 \
--volume nextcloud_aio_mastercontainer:/mnt/docker-aio-config \
--volume /var/run/docker.sock:/var/run/docker.sock:ro \
--env NEXTCLOUD_DATADIR="/home" \
nextcloud/all-in-one:latest
echo '
server {
    listen 80;
    listen [::]:80;            # comment to disable IPv6

    if ($scheme = "http") {
        return 301 https://$host$request_uri;
    }

    listen 443 ssl http2;      # for nginx versions below v1.25.1
    listen [::]:443 ssl http2; # for nginx versions below v1.25.1 - comment to disable IPv6

    # listen 443 ssl;      # for nginx v1.25.1+
    # listen [::]:443 ssl; # for nginx v1.25.1+ - keep comment to disable IPv6

    server_name cloud.sdcgvhgj.top;

    location / {
        proxy_pass http://127.0.0.1:10002$request_uri;

        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header X-Forwarded-Scheme $scheme;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Accept-Encoding "";
        proxy_set_header Host $host;
    
        client_body_buffer_size 512k;
        proxy_read_timeout 86400s;
        client_max_body_size 0;
    }

    ssl_certificate /root/trojan/cloud.crt;
    ssl_certificate_key /root/trojan/cloud.key;
 
    ssl_session_timeout 1d;
    ssl_session_cache shared:MozSSL:10m; # about 40000 sessions
    ssl_session_tickets off;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers on;
}
' > /etc/nginx/sites-enabled/cloud
nginx -t
systemctl start nginx
systemctl reload nginx
