FROM nginx:latest

COPY nginx/nginx.conf.template /etc/nginx/nginx.conf.template

CMD /bin/bash -c "envsubst '\$BACKEND_SERVER_HOST \$BACKEND_SERVER_PORT' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf && exec nginx -g 'daemon off;'"
