server_name: "${FULL_DOMAIN}"
pid_file: /data/homeserver.pid
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    resources:
      - names: [client, federation]
        compress: false
database:
  name: psycopg2
  args:
    user: ${POSTGRES_USER}
    password: ${POSTGRES_PASSWORD}
    database: ${POSTGRES_DATABASE}
    host: postgres
    cp_min: 5
    cp_max: 10
log_config: "/data/localhost.log.config"
media_store_path: /data/media_store
registration_shared_secret: "WYZvX0nyFUdHgon&O+d-t0*6BQPZ93YUUvgNdE21246iV__ON,"
report_stats: false
macaroon_secret_key: "=HZm.yIDFLvUPuCgcPUTHgs#rBNc0,7.yjp5aKxD~4~vMPn-mH"
form_secret: "M:Vm6=sGZdQGHDm+ktcbZN1zJqZZ0Nzx~i3vFL+lgRl~Whx:Wj"
signing_key_path: "/data/localhost.signing.key"
trusted_key_servers:
  - server_name: "matrix.org"
turn_uris:
  - "stun:${FULL_DOMAIN}:3478"
  - "turn:${FULL_DOMAIN}:3478?transport=udp"
  - "turn:${FULL_DOMAIN}:3478?transport=tcp"
  - "turns:${FULL_DOMAIN}:5349?transport=udp"
  - "turns:${FULL_DOMAIN}:5349?transport=tcp"
turn_shared_secret: ${TURN_RANDOM_SECRET}
turn_user_lifetime: 86400000