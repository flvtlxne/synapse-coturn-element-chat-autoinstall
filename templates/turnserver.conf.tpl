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

verbose

no-loopback-peers
no-multicast-peers
