# docker-znuny

[![Build](https://github.com/CygnusNetworks/docker-znuny/actions/workflows/build.yml/badge.svg)](https://github.com/CygnusNetworks/docker-znuny/actions/workflows/build.yml)
[![Watch LTS](https://github.com/CygnusNetworks/docker-znuny/actions/workflows/watch-lts.yml/badge.svg)](https://github.com/CygnusNetworks/docker-znuny/actions/workflows/watch-lts.yml)
[![GitHub license](https://img.shields.io/github/license/CygnusNetworks/docker-znuny)](https://github.com/CygnusNetworks/docker-znuny/blob/main/LICENSE)
[![GitHub last commit](https://img.shields.io/github/last-commit/CygnusNetworks/docker-znuny)](https://github.com/CygnusNetworks/docker-znuny/commits/main)
[![Docker Image Version](https://img.shields.io/docker/v/cygnusnetworks/znuny?sort=semver&label=docker%20hub)](https://hub.docker.com/r/cygnusnetworks/znuny)
[![Docker Pulls](https://img.shields.io/docker/pulls/cygnusnetworks/znuny)](https://hub.docker.com/r/cygnusnetworks/znuny)
[![GHCR](https://img.shields.io/badge/ghcr.io-cygnusnetworks%2Fznuny-blue)](https://github.com/CygnusNetworks/docker-znuny/pkgs/container/znuny)
[![Znuny LTS](https://img.shields.io/badge/Znuny-LTS%206.5-informational)](https://download.znuny.org/)

Debian-based **[Znuny](https://www.znuny.org/) LTS** Docker images built from the official source tarball.

> **Not an official Znuny GmbH image.** This is community packaging by
> [CygnusNetworks](https://github.com/CygnusNetworks). Znuny itself remains
> AGPL-3.0; see [License](#license).

## Images

| Registry | Image |
|----------|--------|
| GitHub Container Registry | `ghcr.io/cygnusnetworks/znuny` |
| Docker Hub | `docker.io/cygnusnetworks/znuny` |

### Tags

| Tag | Meaning |
|-----|---------|
| `6.5.22` (example) | Exact Znuny LTS patch version (reproducible pin) |
| `6.5` | Latest built patch on the 6.5 LTS line |
| `stable` | Current LTS image (same as newest `6.5.x` we publish) |
| `latest` | Alias of `stable` (Docker convention) |

**Naming note:** Znuny’s product line also has a “Stable” track (7.x) separate
from **LTS 6.5**. Our image tag `stable` means *current LTS image*, not Znuny 7.

New LTS 6.5.x releases are detected automatically (see [Update policy](#update-policy)).

### What’s inside

- Base: `debian:trixie-slim`
- Znuny from [download.znuny.org](https://download.znuny.org/) (SHA-256 verified at build)
- Apache 2 + `mod_perl` (prefork MPM)
- supervisord (Apache + cron)
- Znuny daemon + cron jobs started by the entrypoint
- Healthcheck against `/otrs/index.pl`

## Quick start

```bash
docker pull ghcr.io/cygnusnetworks/znuny:stable
# or: docker pull cygnusnetworks/znuny:stable
```

Minimal stack (MariaDB + Znuny):

```bash
cd examples
cp Config.pm.example Config.pm
# edit Config.pm if needed
docker compose up -d
```

Open `http://localhost:8080/otrs/installer.pl` for a fresh database, or point
`Config.pm` at an existing Znuny/OTRS database.

## Volume design

Unlike images that put the entire `/opt/otrs/Kernel` tree in a named volume
(which makes image upgrades ineffective), **application code stays in the
image**. Mount only local state:

| Path | Required | Purpose |
|------|----------|---------|
| `/opt/otrs/Kernel/Config.pm` | yes | DB credentials and site config |
| `/opt/otrs/Custom` | no | Local code overrides |
| `/opt/otrs/var/article` | only with `ArticleStorageFS` | Article files on disk |

Example:

```bash
docker run -d --name znuny \
  -p 8080:80 \
  -v "$PWD/Config.pm:/opt/otrs/Kernel/Config.pm:ro" \
  ghcr.io/cygnusnetworks/znuny:6.5.22
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ZNUNY_SKIP_REBUILD` | unset | Set to `1` to skip package reinstall, config rebuild, and cache delete |
| `ZNUNY_SKIP_DAEMON` | unset | Set to `1` to skip cron install and Znuny daemon start |

Passing a command bypasses boot entirely:

```bash
docker run --rm -it \
  -v "$PWD/Config.pm:/opt/otrs/Kernel/Config.pm:ro" \
  ghcr.io/cygnusnetworks/znuny:stable \
  bash
```

## Entrypoint behaviour

On normal start the entrypoint:

1. Runs `otrs.SetPermissions.pl`
2. Waits for the database (`Maint::Database::Check`, up to ~5 minutes)
3. Unless `ZNUNY_SKIP_REBUILD=1`:
   - `Admin::Package::ReinstallAll` (restores OPM package files after container recreate)
   - `Maint::Config::Rebuild`
   - `Maint::Cache::Delete`
4. Unless `ZNUNY_SKIP_DAEMON=1`: installs cron jobs and starts `otrs.Daemon.pl`
5. `exec` supervisord (Apache + cron)

### OPM packages

Installed package **files** live in the container filesystem and are lost when
the container is recreated. Package metadata remains in the database. The
entrypoint runs `Admin::Package::ReinstallAll` on boot so files are restored
from the package repository.

## Reverse proxy / SSO

Apache is configured to map `X-Forwarded-User` to `REMOTE_USER` for
`Kernel::System::Auth::HTTPBasicAuth` (and similar SSO frontends):

```apache
SetEnvIf X-Forwarded-User "(.*)" REMOTE_USER=$1
```

Terminate TLS and authentication at your reverse proxy, then forward the
authenticated username in `X-Forwarded-User`.

## Optional build-time patches

Place unified diffs under `patches/<ZNUNY_VERSION>/` (e.g.
`patches/6.5.22/01-foo.patch`). They are applied with `patch -p1` during the
image build. The published images ship **without** custom patches.

## Build locally

```bash
docker build \
  --build-arg ZNUNY_VERSION=6.5.22 \
  -t znuny:6.5.22 \
  .
```

Requirements at build time: network access to `download.znuny.org` for the
tarball and `.sha256` checksum.

## Update policy

| Trigger | Behaviour |
|---------|-----------|
| Push to `main` | Rebuilds the configured default LTS version |
| Daily schedule (`watch-lts.yml`) | Detects new `rel-6_5_*` tags on [znuny/Znuny](https://github.com/znuny/Znuny); builds if the image tag is missing |
| `workflow_dispatch` | Manual build for a given version |

CI secrets (org or repo): `DOCKER_USERNAME`, `DOCKER_TOKEN` for Docker Hub.
GHCR uses the built-in `GITHUB_TOKEN`.

Floating tags `6.5`, `stable`, and `latest` are updated when a build is marked
as the current LTS line head.

## Security notes

- Upstream tarball integrity is checked via official `.sha256` files
- No secrets are baked into the image; use a mounted `Config.pm` or secrets
- Znuny historically runs as user `otrs` with Apache; the image follows that model
- Prefer pinning to an exact version (`6.5.x`) in production

## Related links

- [Znuny project](https://www.znuny.org/)
- [Znuny source](https://github.com/znuny/Znuny)
- [Downloads](https://download.znuny.org/)
- [Documentation](https://doc.znuny.org/)

## License

- **This repository** (Dockerfiles, scripts, docs): [MIT](LICENSE)
- **Znuny** software inside the image: [AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0.html)
- Debian packages retain their respective licenses

## Disclaimer

This project is not affiliated with or endorsed by Znuny GmbH. Use at your own
risk. Always test upgrades in a non-production environment.
