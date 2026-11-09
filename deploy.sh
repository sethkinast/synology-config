#!/usr/bin/env bash
# deploy.sh — push this repo's compose files to the Synology NAS and restart the stack.
#
# The repo is the source of truth; the NAS is a deployment target only.
# Edits happen here, never directly on the NAS, so the two can't drift.
#
# Usage:
#   ./deploy.sh            show what would change, ask, then deploy
#   ./deploy.sh --check    show what would change and stop
#   ./deploy.sh --yes      deploy without asking
#
# Env (export them, or put them in a .env.local that is NOT committed):
#   NAS_HOST  NAS hostname or SSH alias, e.g. lil.home.kina.st (required)
#   NAS_USER  SSH user on the NAS (default: current user)
#   NAS_PATH  compose directory on the NAS (default: /volume1/docker)
#   NAS_PORT  SSH port (default: 22)
#
# NAS_HOST may be an alias from ~/.ssh/config — any ProxyJump or key
# settings on that alias apply.
#
# Only docker-compose.yml and xbase.yml are deployed. The NAS .env is never
# touched: it holds secrets and is gitignored for a reason.
set -euo pipefail

cd "$(dirname "$0")"

CHECK=false
YES=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=true; shift ;;
    --yes)   YES=true; shift ;;
    --help|-h)
      sed -n '2,/^set -euo pipefail$/p' "$0" | grep -v '^set -euo pipefail$' | sed 's/^# \?//'
      exit 0 ;;
    *) echo "unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

NAS_HOST="${NAS_HOST:-}"
NAS_USER="${NAS_USER:-${USER:-$(whoami)}}"
NAS_PATH="${NAS_PATH:-/volume1/docker}"
NAS_PORT="${NAS_PORT:-22}"

if [[ -z "$NAS_HOST" ]]; then
  echo "NAS_HOST is not set. Export it first, e.g.:" >&2
  echo "  export NAS_HOST=lil.home.kina.st" >&2
  exit 2
fi

FILES=(docker-compose.yml xbase.yml)
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { echo "missing $f in $(pwd)" >&2; exit 2; }
done

SSH=(ssh -p "$NAS_PORT")
RSYNC_BASE=(rsync -az --checksum --itemize-changes -e "ssh -p $NAS_PORT")

# Warn if deploying uncommitted work: it would run on the NAS without
# ever landing in the repo.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "warning: uncommitted changes in the repo — they will deploy but are not committed" >&2
  fi
fi

# Dry run first, so the delta is visible before anything is overwritten.
# Itemized lines starting with '>' are files that would actually change.
echo "=== changes to deploy to ${NAS_USER}@${NAS_HOST}:${NAS_PATH} ==="
DIFF_OUTPUT="$("${RSYNC_BASE[@]}" --dry-run "${FILES[@]}" "${NAS_USER}@${NAS_HOST}:${NAS_PATH}/")"
echo "$DIFF_OUTPUT"
CHANGES="$(echo "$DIFF_OUTPUT" | grep -E '^>' || true)"

if [[ -z "$CHANGES" ]]; then
  echo "already in sync — nothing to deploy."
  exit 0
fi

if [[ "$CHECK" == true ]]; then
  echo "(--check: stopping here, nothing deployed.)"
  exit 0
fi

if [[ "$YES" != true ]]; then
  read -r -p "Deploy these changes? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "aborted."; exit 0; }
fi

# Back up the live files on the NAS before overwriting, so a bad deploy
# is one cp away from being undone.
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${NAS_PATH}/.deploy-backups/${TS}"
"${SSH[@]}" "${NAS_USER}@${NAS_HOST}" \
  "mkdir -p '$BACKUP_DIR' && for f in ${FILES[*]}; do [ -f '$NAS_PATH'/\$f ] && cp '$NAS_PATH'/\$f '$BACKUP_DIR'/; done && echo backed up to $BACKUP_DIR"

# Push the files.
"${RSYNC_BASE[@]}" "${FILES[@]}" "${NAS_USER}@${NAS_HOST}:${NAS_PATH}/"

# Validate the new config against the NAS .env, then restart the stack.
# If validation fails, the old containers keep running — nothing restarts.
"${SSH[@]}" "${NAS_USER}@${NAS_HOST}" \
  "cd '$NAS_PATH' && docker compose config -q && docker compose up -d"

echo "deployed. Live backup: ${NAS_USER}@${NAS_HOST}:${BACKUP_DIR}"
