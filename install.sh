#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# temper installer: installs ONLY, never applies anything.
# Usage:
#   ./install.sh [--prefix /usr/local] [--yes]
#   curl -fsSL URL/install.sh | bash -s -- --yes   # NOT recommended blindly:
#   read the script first: download it, read it, then run it with --yes.
#   ./install.sh --tag v0.4.0 --sha256 <sum> [--prefix ...]  # pinned release
# No telemetry. No configuration changes. No services touched.
# shellcheck shell=bash
set -euo pipefail

PREFIX="/usr/local"
YES=0
TAG=""
SHA=""
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --prefix) PREFIX="${2:-/usr/local}" && shift 2 ;;
  --yes) YES=1 && shift ;;
  --tag) TAG="${2:-}" && shift 2 ;;
  --sha256) SHA="${2:-}" && shift 2 ;;
  apply)
    printf 'error: the installer never applies changes (refusing "apply")\n' >&2
    exit 2
    ;;
  --help | -h)
    sed -n '2,10p' "$0"
    exit 0
    ;;
  *)
    printf 'error: unknown arg: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

if [[ ! -t 0 && "$YES" != "1" ]]; then
  printf 'Refusing: stdin is not a terminal (piped install).\n'
  printf 'Read the script first, then run one of:\n'
  printf '  curl -fsSL <url>/install.sh -o install.sh && less install.sh\n'
  printf '  bash install.sh --yes [--prefix DIR]\n'
  exit 2
fi

WORK="$SRC_DIR"
if [[ -n "$TAG" ]]; then
  # Pinned release install: tag + expected SHA256 required.
  if [[ -z "$SHA" ]]; then
    printf 'error: --tag requires --sha256 <expected-sum>\n' >&2
    exit 2
  fi
  base="${TEMPER_RELEASE_BASE:-https://github.com/KanekiDevPro/temper/releases/download}"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  printf 'downloading %s ...\n' "$TAG"
  curl -fsSL --max-time 120 "$base/$TAG/temper-$TAG.tar.gz" -o "$WORK/pkg.tar.gz" || {
    printf 'error: download failed\n' >&2
    exit 1
  }
  actual="$(sha256sum "$WORK/pkg.tar.gz" | awk '{print $1}')"
  if [[ "$actual" != "$SHA" ]]; then
    printf 'error: checksum mismatch (got %s)\n' "$actual" >&2
    exit 1
  fi
  tar xzf "$WORK/pkg.tar.gz" -C "$WORK"
  SRC_DIR="$WORK/temper-$TAG"
  if [[ ! -f "$SRC_DIR/optimizer.sh" ]]; then
    printf 'error: bad tarball layout (no optimizer.sh)\n' >&2
    exit 1
  fi
  trap - EXIT
fi

if [[ ! -f "$SRC_DIR/optimizer.sh" || ! -f "$SRC_DIR/VERSION" ]]; then
  printf 'error: %s is not a temper tree\n' "$SRC_DIR" >&2
  exit 1
fi

DEST="$PREFIX/share/temper"
BINLINK="$PREFIX/bin/temper"
mkdir -p "$DEST" "$(dirname "$BINLINK")"
cp -a "$SRC_DIR/optimizer.sh" "$SRC_DIR/VERSION" "$SRC_DIR/LICENSE" "$DEST/" 2>/dev/null || cp -a "$SRC_DIR/optimizer.sh" "$SRC_DIR/VERSION" "$DEST/"
for d in lib modules scanner profiles bench data templates completion web; do
  if [[ -d "$SRC_DIR/$d" ]]; then
    rm -rf "${DEST:?}/$d"
    cp -a "$SRC_DIR/$d" "$DEST/"
  fi
done
if [[ -f "$SRC_DIR/docs/temper.1" ]]; then
  mkdir -p "$PREFIX/share/man/man1"
  cp -a "$SRC_DIR/docs/temper.1" "$PREFIX/share/man/man1/temper.1"
fi
{
  printf 'prefix=%s\n' "$PREFIX"
  printf 'version=%s\n' "$(cat "$DEST/VERSION")"
  printf 'date=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"
} >"$DEST/.install-manifest"
ln -sf "$DEST/optimizer.sh" "$BINLINK" 2>/dev/null || true
if [[ ! -L "$BINLINK" ]]; then
  # No symlink rights (e.g. Windows/MSYS copies instead): wrapper instead.
  printf '#!/usr/bin/env bash\nexec "%s/optimizer.sh" "$@"\n' "$DEST" >"$BINLINK"
fi
chmod +x "$DEST/optimizer.sh"
printf 'installed temper %s to %s (run: temper --help)\n' "$(cat "$DEST/VERSION")" "$DEST"
printf 'nothing was configured: run temper scan first, then --dry-run.\n'
