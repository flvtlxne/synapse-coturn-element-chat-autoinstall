http:
  middlewares:
    basic-auth:
      basicAuth:
        users:
            - "${TRAEFIK_BASIC_AUTH}"