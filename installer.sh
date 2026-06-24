#!/usr/bin/env bash
#
# installer.sh - one-shot installer for `ab`.
#
# Downloads the latest version of `ab` from GitHub (master branch) and installs
# it into /usr/local/bin, overwriting any existing copy.
#
# Usage (must run as root, e.g. via sudo):
#   curl --fail --location --silent --show-error \
#     https://raw.githubusercontent.com/acortiana/ab/master/installer.sh | sudo bash
#
# MAINTAINER CONVENTION (same as `ab`):
#   All calls to external commands ALWAYS use the long form of options where
#   available (--fail, --location, --mode, ...). Keeps the code self-explanatory.
#
set -euo pipefail

REPO_RAW_URL="https://raw.githubusercontent.com/acortiana/ab/master/ab"
DEST="/usr/local/bin/ab"

die() { echo "installer: $*" >&2; exit 1; }

# Preflight: must run as root and need curl to download.
[ "$(id -u)" -eq 0 ] || die "Run as root, e.g. with sudo."
command -v curl >/dev/null 2>&1 || die "curl is required but was not found."

# Download to a temporary file, cleaned up on exit.
tmp="$(mktemp)"
trap 'rm --force "$tmp"' EXIT

curl --fail --location --silent --show-error --output "$tmp" "$REPO_RAW_URL" \
  || die "Download failed from $REPO_RAW_URL"

# Install atomically: create/overwrite with the right permissions in one step.
install --mode 755 "$tmp" "$DEST" || die "Could not install to $DEST"

echo "ab installed at $DEST"
echo "Run 'ab' to get started (see README for usage)."
