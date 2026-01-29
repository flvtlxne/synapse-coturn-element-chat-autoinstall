FROM nginx:latest

COPY nginx/templates/nginx.conf.tpl /etc/nginx/templates/nginx.conf.tpl

CMD envsubst \ 
    '$FULL_DOMAIN $PGADMIN_PREFIX $GRAFANA_PATH_PREFIX $PROMETHEUS_PREFIX' \ 
    < /etc/nginx/templates/nginx.conf.tpl \ 
    > /etc/nginx/nginx.conf \ 
    && nginx -g 'daemon off;'