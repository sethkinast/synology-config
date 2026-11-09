# synology-config

A Dockerfile for my Synology NAS running \*arrs and Jellyfin/Jellyseerr.

Caddy reverse-proxies the services so that they are accessible on my domain without having to use port numbers or self-signed certificates.

## Deploy

`deploy.sh` pushes `docker-compose.yml` and `xbase.yml` to the NAS and restarts the stack. The repo is the source of truth — edit here, never directly on the NAS, so the two can't drift.

```sh
export NAS_HOST=lil.home.kina.st   # required; may be an SSH alias from ~/.ssh/config
export NAS_USER=seth               # optional, defaults to current user
export NAS_PATH=/volume1/docker    # optional
./deploy.sh            # show the diff, ask, then deploy
./deploy.sh --check    # show the diff only
./deploy.sh --yes      # deploy without asking
```

The script shows exactly what would change before deploying, backs up the live files on the NAS to `.deploy-backups/<timestamp>/` first, validates the new config, then runs `docker compose up -d`. The NAS `.env` is never deployed or overwritten. If the repo and the NAS ever drift, `./deploy.sh --check` shows the delta before anything is overwritten.
