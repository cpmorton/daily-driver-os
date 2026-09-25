# 0006. Rootless podman only; the Docker CLI runs podman

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Bluefin's developer setup defaults to Docker Engine and the `docker` group. That
group is equivalent to root. Devcontainers still expect a `docker` command.

## Decision

- Rootful podman is masked (`podman.socket`, `podman.service`,
  `podman-restart`, `podman-auto-update`), including the system socket that
  finpilot's `10-overlay.sh` enables. Every user gets a rootless
  `podman.socket`.
- `podman-docker` makes `/usr/bin/docker` run podman. `/usr/local/bin/docker-compose`
  links to podman-compose. `/usr/lib/environment.d/60-docker-host.conf` points
  `DOCKER_HOST` at the user's socket for every app, GUI included.
- podman-docker's *system* tmpfiles entry (`/run/docker.sock` → the rootful
  socket) is masked; its per-user entry is kept. The mask is an empty
  `/etc/tmpfiles.d/podman-docker.conf`, not a `/dev/null` symlink: bootc's
  `var-tmpfiles` lint fails with "a path led outside of the filesystem" on
  an absolute symlink there, and systemd treats an empty file as a mask too.

## Alternatives

- **Docker Engine + `docker` group:** root-equivalent for every member.
- **Per-user VS Code settings (`dev.containers.dockerPath: podman`):** works,
  but lives in the home and must be repeated per user; see
  [0004](0004-where-software-goes.md).

## Consequences

- Scripts that need real Docker features (buildx builders, Docker Desktop
  extensions, Swarm) won't work. `docker` prints a one-line notice unless
  `/etc/containers/nodocker` exists (it does).
- Bind mounts in devcontainers may need `"runArgs": ["--userns=keep-id"]`.

## Verification

podman's upstream `rpm/podman.spec`, `docker/docker.in`,
`docker/podman-docker.sh` and `contrib/systemd/system/podman-docker.conf`, read
2026-09-23. systemd's `environment.d(5)` for `${VAR}` expansion. On the
pinned Silverblue 44 base (2026-09-25): `bootc container lint` fails with the
`/dev/null` symlink and passes with the empty file, and
`systemd-tmpfiles --cat-config` reports the empty file as a mask.
[VERIFY in a VM: `systemctl --user show-environment | grep DOCKER_HOST`, and a
compose-based devcontainer.]

## Revisit when

A project genuinely needs Docker Engine. Run it in a VM, not on the host.
