# CLAUDE.md

Guide for working on this repository. Also read `README.md` for user-facing usage.

## What it is

`ab` is a Bash CLI that acts as a thin wrapper around `docker` to manage
disposable containers. **All the code lives in the single file `ab`** (a
self-contained Bash executable). There is no build step and no dependencies
beyond `docker` and the standard tools of any Linux system.

## Non-negotiable principles

- **KISS.** The target audience is sysadmins/devops; the code must stay
  readable and modifiable even by people who aren't expert programmers. Always
  prefer the simplest, most compatible solution.
- **Long-form options everywhere.** In every call to an external command
  (`docker`, `sed`, `mkdir`, etc.) use the long form of flags where it exists
  (`--detach` not `-d`, `--volume` not `-v`, `--interactive --tty` not `-it`,
  `--name`, `--env`, `--user`, ...). It makes the code self-explanatory. There's
  a header comment that states this: keep it accurate.
- **A single executable.** Do not introduce additional source files or
  dependencies.
- **Mandatory preflight.** Every subcommand that uses Docker first goes through
  `preflight_docker` (docker installed + daemon reachable) and, except for
  `init`, through `require_project` (`.env` with `AB_PROJECT=true`).

## Structure of `ab`

1. Header + `set -euo pipefail` + `DEFAULT_*` constants.
2. Helpers: `die`, `warn`, `usage`, `preflight_docker`, `require_project`,
   `load_env`, `shell_quote`, `random_name`, `ask`, `ask_yes_no`.
3. Subcommands: `cmd_init`, `cmd_create`, `cmd_destroy`, `cmd_shell`, `cmd_root`
   (plus the helpers `container_state`, `ensure_running`).
4. `main` with the `case` dispatch on `$1`, with `main "$@"` at the bottom.

`.env` is the only configuration source read at runtime (`load_env` does
`set -a; . ./.env; set +a`). `.env.example` is documentation only, never read.

## Important design decisions (non-obvious context)

- **User/group inside the container = the ones chosen in `.env`**
  (`USERNAME`/`GROUPNAME`), **not** the image's default user. UID/GID always
  come from the host (`id -u`/`id -g`), so ownership on bind-mounts is correct
  without `chown`.
- **Provisioning via direct edits to `/etc/passwd` and `/etc/group`** (in
  `cmd_create`, inside a `docker exec ... sh -c '...'`). Chosen instead of
  `useradd`/`adduser` to have **a single portable code path** across any
  distro, Alpine included (busybox has no `useradd` without `shadow`). The
  `sed` calls remove conflicting lines (by name or by UID/GID) and then the
  correct line is recreated.
- **Dynamic login shell.** During provisioning, `bash` is set if present in
  the image, otherwise `/bin/sh`. `cmd_shell`/`cmd_root` read field 7 of
  `/etc/passwd` with fallback `/bin/sh`: **never hardcode `bash`** (it would
  break Alpine).
- **`CONTAINER_CMD` left unquoted in `docker run`** (`... "$BASE_IMAGE"
  $CONTAINER_CMD`): the word-splitting is intentional (`sleep infinity` -> two
  arguments). In `.env`, instead, it is quoted with single quotes via
  `shell_quote`.
- **`random_name` in a subshell with `set +o pipefail`**: without it, the
  `SIGPIPE` sent to `tr` when `head` closes the pipe would make the function
  fail.
- **Host-root guard:** `cmd_create` exits with an error if the host is UID 0,
  because UID 0 would conflict with the container's `root` user during
  provisioning.
- **`provision.d/` and `home/startup.d/` naming convention is run-parts
  style**, centralized in the `run_scripts_dir` helper (matched with `case
  "$name" in *[!A-Za-z0-9_-]*) continue ;; esac`). Active script names
  contain only `[A-Za-z0-9_-]`. This single rule does triple duty:
  alphabetical ordering (hence the `NN-` prefix convention), "disable via
  rename" (any suffix containing a dot, e.g. `.disabled`, is skipped), and
  excluding `README.md`/documentation from execution — with no extra
  special-casing needed. The same helper's glob-based iteration also makes a
  missing/optional directory a silent no-op for free (no `[ -d ]` check
  needed): see `home/startup.d/`.
- **`provision.d/` runs as root, `home/startup.d/` runs as the unprivileged
  user — intentionally different.** `provision.d/` exists *for* root-level
  setup, in a directory only the host project owner populates.
  `home/startup.d/`, instead, lives inside `home/`, which the container user
  owns (`USERNAME`/`GROUPNAME` from `.env`): running its content as root
  would let anything that lands there — even unintentionally — execute as
  root on the next restart. Hence `run_scripts_dir` is called with `--user
  root` for one and `--user "$USERNAME" --env HOME=...` for the other.
- **`home/startup.d/` failures only `warn`, `provision.d/` failures `die`.**
  A failed one-shot provisioning script means "the container isn't ready",
  so `cmd_create` aborts and leaves the container for inspection. A failed
  *recurring* startup script must never lock the user out of `ab shell`/`ab
  root`/`ab create` — that would be hostile precisely when they need to get
  in to debug it. `run_scripts_dir` itself stays neutral (it warns and
  returns non-zero on the first problem); each call site decides whether
  that's fatal.

## Conventions when modifying

- Host values passed to the container go through `--env`, never interpolated
  into the command text, to avoid quoting/escaping issues.
- User-facing messages are in English. Errors via `die` (stderr, exit 1);
  non-fatal warnings via `warn`.
- Text values written to `.env` go through `shell_quote`.

## Testing (without Docker)

This development environment **has no Docker**, so the code paths that use it
(`create`/`destroy`/`shell`/`root`) cannot be exercised here. What can still be
verified:

- `bash -n ab` for syntax.
- `ab init` in a temporary empty directory (piping inputs with `printf`),
  then check `.env`/`.env.example` and the round-trip via sourcing.
- Error paths (non-empty dir, command run outside a project, etc.).
- The **provisioning logic** by simulating the body of the `sh -c` with `sh`
  against fake local `passwd`/`group` files (scenarios: UID/GID overlap, no
  overlap, root/Alpine only, name collision).

Real end-to-end testing: only on a machine with Docker (see the "Verification"
section of the plan and the examples in `README.md`).

## Out of scope (do not implement)

Networking/ports, extra env vars, additional volumes beyond `home/`, `bin/`
and `provision.d/`, resource limits, multi-container, image builds, a `stop`
subcommand.
