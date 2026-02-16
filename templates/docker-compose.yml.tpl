# ----------------------- Traefik ----------------------------
services:
  traefik:
    image: traefik:v3.6.7
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./traefik/acme.json:/letsencrypt/acme.json
      - ./traefik/dynamic:/etc/traefik/dynamic:ro
    networks:
      - backend-proxy-network
      - monitoring
    labels:
      - traefik.enable=true

  # ----------------------- Element ----------------------------
  synapse:
    image: matrixdotorg/synapse:latest
    container_name: matrix_synapse
    user: "991:991"
    restart: unless-stopped
    volumes:
      - ./synapse:/data
    environment:
      - SYNAPSE_SERVER_NAME=${FULL_DOMAIN}
      - SYNAPSE_REPORT_STATS=no
    expose:
      - "8008"
    depends_on:
      - postgres
    networks:
      - backend-proxy-network
    labels:
      - traefik.enable=true

      - traefik.http.routers.synapse.rule=Host(`${FULL_DOMAIN}`) && (PathPrefix(`/_matrix`) || PathPrefix(`/_synapse`))
      - traefik.http.routers.synapse.entrypoints=websecure
      - traefik.http.routers.synapse.tls.certresolver=letsencrypt

      - traefik.http.services.synapse.loadbalancer.server.port=8008


  postgres:
    image: postgres:15
    container_name: postgres
    restart: unless-stopped
    environment:
      - POSTGRES_DB=${POSTGRES_DATABASE}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_INITDB_ARGS=--encoding=UTF-8 --lc-collate=C --lc-ctype=C
    expose:
      - "5432"
    volumes:
      - ./postgres:/var/lib/postgresql/data
    networks:
      - backend-proxy-network
      - database-management-network

  element:
    image: vectorim/element-web:latest
    container_name: matrix_element
    restart: unless-stopped
    volumes:
      - ./element/config.json:/app/config.json
    expose:
      - "80"
    networks:
      - backend-proxy-network
    labels:
      - traefik.enable=true

      - traefik.http.routers.element.rule=Host(`${FULL_DOMAIN}`)
      - traefik.http.routers.element.entrypoints=websecure
      - traefik.http.routers.element.tls.certresolver=letsencrypt

      - traefik.http.services.element.loadbalancer.server.port=80

  turn:
    image: instrumentisto/coturn
    container_name: turn
    restart: unless-stopped
    network_mode: "host"
    volumes:
      - ./turn/turnserver.conf:/etc/coturn/turnserver.conf:ro

  matrix-wellknown:
    image: traefik/whoami
    container_name: matrix_wellknown
    restart: unless-stopped
    networks:
      - backend-proxy-network

  # ------------------------------------------------------------
  
  # ----------------------- PGAdmin ----------------------------
  pgadmin:
    image: dpage/pgadmin4
    container_name: pgadmin
    restart: unless-stopped
    env_file:
      - .env
    environment:
      SCRIPT_NAME: /${PGADMIN_PREFIX}
      PGADMIN_DISABLE_POSTFIX: true
      PGADMIN_LISTEN_ADDRESS: 0.0.0.0
      PGADMIN_LISTEN_PORT: 80
    volumes:
      - pg-admin-data:/var/lib/pgadmin
    networks:
      - database-management-network
      - backend-proxy-network
    labels:
      - traefik.enable=true

      - traefik.http.routers.pgadmin.rule=Host(`${FULL_DOMAIN}`) && PathPrefix(`/pgadmin`)
      - traefik.http.routers.pgadmin.entrypoints=websecure
      - traefik.http.routers.pgadmin.tls.certresolver=letsencrypt
      - traefik.http.routers.pgadmin.middlewares=basic-auth@file

      - traefik.http.services.pgadmin.loadbalancer.server.port=80

  # ------------------------------------------------------------

  # ----------------------- Metrics ----------------------------
  prometheus:
    image: prom/prometheus
    container_name: prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    env_file:
      - .env
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.route-prefix=/${PROMETHEUS_PREFIX}'
      - '--web.external-url=${PROMETHEUS_EXTERNAL_URL}'
    restart: unless-stopped
    networks:
      - monitoring
    labels:
      - traefik.enable=true

      - traefik.http.routers.prometheus.rule=Host(`${FULL_DOMAIN}`) && PathPrefix(`/prometheus`)
      - traefik.http.routers.prometheus.entrypoints=websecure
      - traefik.http.routers.prometheus.tls.certresolver=letsencrypt
      - traefik.http.routers.prometheus.middlewares=basic-auth@file

      - traefik.http.services.prometheus.loadbalancer.server.port=9090

  cadvisor:
    image: ghcr.io/google/cadvisor:latest
    container_name: cadvisor
    expose:
      - "8080"
    restart: unless-stopped
    privileged: true
    devices:
      - /dev/kmsg
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
    networks:
      - monitoring

  node-exporter:
    image: prom/node-exporter
    container_name: node_exporter
    restart: unless-stopped
    networks:
      - monitoring

  grafana:
    image: grafana/grafana
    container_name: grafana
    volumes:
      - grafana-data:/var/lib/grafana
    environment:
      - GF_SERVER_ROOT_URL=/${GRAFANA_PATH_PREFIX}
      - GF_SERVER_SERVE_FROM_SUB_PATH=true
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
    expose:
      - "3000"
    restart: unless-stopped
    networks:
      - monitoring
    labels:
      - traefik.enable=true

      - traefik.http.routers.grafana.rule=Host(`${FULL_DOMAIN}`) && PathPrefix(`/grafana`)
      - traefik.http.routers.grafana.entrypoints=websecure
      - traefik.http.routers.grafana.tls.certresolver=letsencrypt
      - traefik.http.routers.grafana.middlewares=basic-auth@file

      - traefik.http.services.grafana.loadbalancer.server.port=3000

  # ---------------------------------------------------------
  
volumes:
  pg-admin-data:
  grafana-data:

networks:
  backend-proxy-network:
  database-management-network:
  monitoring: