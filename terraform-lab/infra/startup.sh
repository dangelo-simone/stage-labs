#!/bin/bash
set -euo pipefail

REPO_URL=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/repo-url")
CLONE_DIR="/opt/stage-labs"
WEBROOT="$CLONE_DIR/terraform-lab/site-content/live"

apt-get update
apt-get install -y nginx openssl git


if [ -d "$CLONE_DIR/.git" ]; then
  git -C "$CLONE_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$CLONE_DIR"
fi

#self signed ssl, l'identità è l'ip pubblico della vm, conosciuto solo dopo l'avvio, preso dal metadata server
IP=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip")
mkdir -p /etc/nginx/ssl
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /etc/nginx/ssl/selfsigned.key \
  -out    /etc/nginx/ssl/selfsigned.crt \
  -subj   "/C=IT/ST=Lombardia/L=Milano/O=F2Lab/CN=${IP}" \
  -addext "subjectAltName=IP:${IP}" #se no alcuni browser fanno stories

#file nginx
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80 default_server;
    #variabili escaped perché se no terraform le interpreta come sue
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl default_server;
    ssl_certificate     /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
    root  $WEBROOT;
    index index.html;
}
EOF
systemctl restart nginx

# cron fa pull ogni 5 minuti
echo "*/5 * * * * root cd $CLONE_DIR && git pull --ff-only >/dev/null 2>&1" \
  > /etc/cron.d/site-pull
