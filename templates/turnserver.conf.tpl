listening-port=3478
tls-listening-port=5349

listening-ip=0.0.0.0
relay-ip=${PUBLIC_IP_ADDR}
external-ip=${PUBLIC_IP_ADDR}
realm=${FULL_DOMAIN}

fingerprint
use-auth-secret
static-auth-secret=${TURN_RANDOM_SECRET}

user-quota=12
total-quota=1200

min-port=49152
max-port=65535

no-cli
no-loopback-peers
no-multicast-peers
no-tcp-relay

denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255