AWS_PROFILE=$PROFILEAWS sudo -E certbot certonly -d $DOMAIN --dns-route53 -m $EMAIL --agree-tos --non-interactive --server https://acme-v02.api.letsencrypt.org/directory
