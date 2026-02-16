http:
  middlewares:
    matrix-server-headers:
      headers:
        customResponseHeaders:
          Content-Type: application/json

    matrix-server-rewrite:
      replacePathRegex:
        regex: ".*"
        replacement: "/"

  routers:
    matrix-wellknown:
      rule: Host(`${FULL_DOMAIN}`) && Path(`/.well-known/matrix/server`)
      entryPoints:
        - websecure
      service: matrix-wellknown
      middlewares:
        - matrix-server-headers
        - matrix-server-rewrite
      tls:
        certResolver: letsencrypt


  services:
    matrix-wellknown:
      loadBalancer:
        servers:
          - url: http://matrix_wellknown