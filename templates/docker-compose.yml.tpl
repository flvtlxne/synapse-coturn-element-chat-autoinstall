services:
  nginx:
    build:
      context: .
      dockerfile: nginx/Dockerfile
    image: sas-messenger-nginx:latest
    container_name: sas_messenger_nginx
    env_file:
      - .env
    ports:
      - 443:443
      - 80:80
    volumes:
      - ${CERT_PATH}/fullchain.pem:/etc/nginx/fullchain.pem
      - ${CERT_PATH}/privkey.pem:/etc/nginx/privkey.pem
    networks:
      - sas-messenger-backend-proxy-network
      - sas-messenger-database-management-network
      - sas-messenger-monitoring
    depends_on:
      - synapse
      - element
    restart: unless-stopped

  # ----------------------- Element ----------------------------
  synapse:
    image: matrixdotorg/synapse:latest
    container_name: sas_messenger_matrix_synapse
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
      - sas-messenger-backend-proxy-network

  postgres:
    image: postgres:15
    container_name: sas_messenger_postgres
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
      - sas-messenger-backend-proxy-network
      - sas-messenger-database-management-network

  element:
    image: vectorim/element-web:latest
    container_name: matrix_element
    restart: unless-stopped
    volumes:
      - ./element/config.json:/app/config.json
    expose:
      - "80"
    networks:
      - sas-messenger-backend-proxy-network

  turn:
    image: instrumentisto/coturn
    container_name: sas_messenger_turn
    restart: unless-stopped
    network_mode: "host"
    volumes:
      - ./turn/turnserver.conf:/etc/coturn/turnserver.conf:ro
  # ----------------------- ------------------------------------
  
  # ----------------------- PGAdmin ----------------------------
  pgadmin:
    image: dpage/pgadmin4
    container_name: sas_messenger_pgadmin
    restart: unless-stopped
    env_file:
      - .env
    environment:
      SCRIPT_NAME: /${PGADMIN_PREFIX}
      PGADMIN_DISABLE_POSTFIX: true
      PGADMIN_LISTEN_ADDRESS: 0.0.0.0
      PGADMIN_LISTEN_PORT: 80
    volumes:
      - sas-messenger-pg-admin-data:/var/lib/pgadmin
    networks:
      - sas-messenger-database-management-network
  # ------------------------------------------------------------

  # ----------------------- Metrics ----------------------------
  prometheus:
    image: prom/prometheus
    container_name: sas_messenger_prometheus
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
      - sas-messenger-monitoring

  node-exporter:
    image: prom/node-exporter
    container_name: sas_messenger_node_exporter
    restart: unless-stopped
    networks:
      - sas-messenger-monitoring

  grafana:
    image: grafana/grafana
    container_name: sas-messenger-grafana
    volumes:
      - sas-messenger-grafana-data:/var/lib/grafana
    environment:
      - GF_SERVER_ROOT_URL=/${GRAFANA_PATH_PREFIX}
      - GF_SERVER_SERVE_FROM_SUB_PATH=true
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
    expose:
      - "3000"
    restart: unless-stopped
    networks:
      - sas-messenger-monitoring
  # ---------------------------------------------------------
  
volumes:
  sas-messenger-pg-admin-data:
  sas-messenger-grafana-data:

networks:
  sas-messenger-backend-proxy-network:
  sas-messenger-database-management-network:
  sas-messenger-monitoring:
