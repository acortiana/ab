# ab

`ab` is a small Bash CLI that simplifies the lifecycle of Docker containers
used as **disposable, sandboxed environments**: interactive shell, testing,
prototyping. It's a thin wrapper around `docker`, with data persisted on the
host in `home/`, `bin/` and `provision.d/`.

- **Single executable**: one self-contained Bash script.
- **No dependencies** beyond `docker` and the standard tools of any Linux system.
- **KISS**: simple, readable code, modifiable even by non-programmers.
- **Consistent UID/GID**: the user inside the container has the same UID/GID as
  the host user, so files in `home/`, `bin/` and `provision.d/` have correct
  ownership without `chown`.

## Requirements

- `docker` installed and the daemon running (with permissions for the current user).
- Run as an **unprivileged user** (not root).

## Installation

Copy the `ab` script into a directory in your `PATH` and make it executable:

```sh
install -m 755 ab ~/.local/bin/ab    # or /usr/local/bin/ab
```

## Operating model (git-like)

1. Create an **empty** directory wherever you want on the host.
2. Initialize it with `ab init` (similar to `git init`).
3. Run subsequent commands **from inside** that directory.

An initialized directory is recognized by the `.env` file containing the line
`AB_PROJECT=true`. Outside an initialized directory, every command other than
`init` exits with an error.

## Commands

| Command      | Description                                                       |
|--------------|-------------------------------------------------------------------|
| `ab init`    | Initialize the current directory (interactive only)              |
| `ab create`  | Create and start the container                                   |
| `ab destroy` | Destroy the container (does **not** touch host data)             |
| `ab shell`   | Open an interactive shell as an unprivileged user                |
| `ab root`    | Open an interactive shell as root                                 |

`shell` and `root` automatically restart the container if it's stopped.

## Example

```sh
mkdir trial && cd trial
ab init        # answer the questions (Enter = default)
ab create      # create and start the container
ab shell       # enter as an unprivileged user
# ... work ...
ab destroy     # remove the container; home/, bin/ and provision.d/ remain intact
```

## `ab init`

Must be run in a **completely empty** directory (dotfiles included).
It's interactive: for each parameter it shows the default in `[]`; press Enter
to accept it or type an alternative value.

| Parameter       | Default                              |
|-----------------|--------------------------------------|
| Container name  | 8 random alphanumeric characters     |
| Base image      | `ubuntu:22.04`                       |
| Username        | `myuser`                             |
| Groupname       | `mygroup`                            |
| Startup command | `sleep infinity`                     |
| Enable X11      | `false`                              |
| Enable Wayland  | `false`                              |

UID and GID are **not** configurable: they are read at runtime from the user
running `ab` (`id -u` / `id -g`).

`init` creates the `home/`, `bin/` and `provision.d/` subdirectories, plus
`home/startup.d/` — both `provision.d/` and `home/startup.d/` are
pre-populated with a `README.md` and a disabled example script (see
"Container provisioning" and "Container startup scripts" below) — the `.env`
file (read at runtime) and the `.env.example` file (full documentation
reference, never read by `ab`).

## Configuration (`.env`)

```sh
AB_PROJECT=true            # project marker, DO NOT remove
CONTAINER_NAME='...'       # container name
BASE_IMAGE='ubuntu:22.04'  # base image
USERNAME='myuser'          # unprivileged user inside the container
GROUPNAME='mygroup'        # primary group
CONTAINER_CMD='sleep infinity'  # main command (PID 1)
ENABLE_X11=false           # X11 graphical support
ENABLE_WAYLAND=false       # Wayland graphical support
```

Text values are wrapped in single quotes: quote them if they contain spaces or
special characters. See `.env.example` for the full documentation of every key.

## User, group and UID/GID management

`ab create` **always** uses the user and group given in `.env`, not the
image's defaults. Provisioning works directly on `/etc/passwd` and
`/etc/group` inside the container (a single method portable across any distro
— Ubuntu, Debian, Fedora, Alpine — without depending on `useradd`/`adduser`/`shadow`):

- creates the `GROUPNAME` group with the **host's GID**;
- creates the `USERNAME` user with the **host's UID**, primary group
  `GROUPNAME`, home `/home/$USERNAME`;
- if a pre-existing user or group **overlaps** (same name, or same host
  UID/GID), the conflicting line is **removed and recreated** correctly.

The user's login shell is `bash` if present in the image, otherwise `/bin/sh`:
this is why `ab shell`/`ab root` also work on images without `bash`
(e.g. Alpine "base").

## Graphical support

Configurable in `.env`, applied by `ab create`. X11 and Wayland are independent
and can be enabled together.

- **X11** (`ENABLE_X11=true`): mounts `/tmp/.X11-unix` and the `Xauthority`
  file (read-only), and passes `DISPLAY`/`XAUTHORITY`.
- **Wayland** (`ENABLE_WAYLAND=true`): mounts only the `wayland-0` socket and
  passes `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR`. This works because the container
  uses the same UID as the host.

## Container provisioning (`provision.d/`)

Right after the container is created, `ab create` runs the scripts found in
`provision.d/`, **as root**, **in alphabetical order**, in the foreground and
attached to the same terminal — so scripts that need user interaction behave
exactly as if you had typed the commands yourself. This is the place to
install packages, clone repositories, write configuration files, and so on.

- Active scripts: executable files whose name contains only letters, digits,
  `_` and `-` (e.g. `10-install-packages`). The leading number sets the
  execution order; leave gaps (10, 20, 30, ...) for future insertions.
- To temporarily disable a script, rename it adding any suffix that contains
  a dot (e.g. `10-install-packages.disabled`): any name with a dot is
  skipped — which is also why `README.md` is never executed.
- Every script **must** end with `exit 0`. If one fails, `ab create` stops,
  reports an error and **leaves the container running** so you can inspect it
  (`ab root`/`ab shell`); destroy it with `ab destroy` before retrying.

See `provision.d/README.md` (created by `ab init`) for the full naming
convention and a working example script.

## Container startup scripts (`home/startup.d/`)

Every time `ab` (re)starts the container — the very first `ab create`, right
after `provision.d/`, and any later restart that `ab shell`/`ab root`
triggers by finding it stopped — it also runs the scripts found in
`home/startup.d/`, **as your unprivileged user**, **in alphabetical order**,
in the foreground and attached to the same terminal. This is the place for
things that must happen on every boot: starting a background service,
syncing dotfiles, regenerating host-dependent configuration, and so on.

It follows the same naming convention as `provision.d/` (run-parts style:
only `[A-Za-z0-9_-]` for active scripts, rename adding a dot-suffix like
`.disabled` to skip one), but differs from it in three important ways:

- **Runs as your unprivileged user, not root.** `home/` is yours: running
  arbitrary content from inside it as root would turn any file that lands
  there into a potential root-execution vector. Need root? Use
  `provision.d/` instead.
- **Scripts must be idempotent.** Unlike `provision.d/` (run once, at
  creation), these can run many times over the container's life.
- **A failing script only produces a warning** — it never blocks `ab create`,
  `ab shell` or `ab root`. Locking you out of your own container because a
  startup script misbehaved would defeat the purpose.

This directory is **optional**: `ab init` creates it, but deleting it is
fine — `ab` simply skips it. Also note that `ab` can only run these scripts
when *it* is what (re)starts the container: a direct `docker start` or a
Docker restart policy would bypass it entirely.

See `home/startup.d/README.md` (created by `ab init`) for the full
convention and a working example script.

## Data persistence

- `./home` is mounted at `/home/$USERNAME` inside the container (its
  `startup.d/` subdirectory is covered in "Container startup scripts" above).
- `./bin` is mounted at `/usr/local/bin` (handy for placing scripts/executables).
- `./provision.d` is mounted at `/usr/local/provision.d` (see "Container
  provisioning" above).
- `ab destroy` removes **only** the container: `home/`, `bin/`, `provision.d/`,
  `.env` and `.env.example` are never touched.

## Out of scope

Networking/ports, extra environment variables, additional volumes, resource
limits, multi-container setups, custom image builds, a `stop` subcommand (the
container stays up until destroyed; `shell`/`root` restart it if stopped).
