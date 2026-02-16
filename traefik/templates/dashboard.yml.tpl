http:
  routers:
    traefik-dashboard:
      rule: Host(`${FULL_DOMAIN}`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))
      entryPoints:
        - websecure
      service: api@internal
      priority: 1000
      middlewares:
        - basic-auth
      tls:
        certResolver: letsencrypt