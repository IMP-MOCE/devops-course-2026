#!/usr/bin/env bash
# Usage: scripts/deploy.sh [--dry-run]
set -euo pipefail
REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
DRY_RUN=false
case "$#:$*" in
    0:) ;;
    1:--dry-run) DRY_RUN=true ;;
    *) die 'Usage: scripts/deploy.sh [--dry-run]' ;;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)" || die 'Not a Git repository'
LOCAL_DIR="${ROOT}/site/"
[[ -f "${LOCAL_DIR}index.html" ]] || die 'site/index.html is missing; nothing was sent'
STATUS="$(git -C "$ROOT" status --porcelain --untracked-files=all)" || die 'Cannot read Git status'
[[ -z "$STATUS" ]] || die 'Uncommitted changes (including staged/untracked); nothing was sent'
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
OPTS=(-avz --checksum --delete --chmod=D755,F644 --no-owner --no-group)
if "$DRY_RUN"; then
    OPTS+=(--dry-run)
else
    [[ -r "$CA_CERT" ]] || die "Trusted certificate is missing: $CA_CERT"
fi
# Exactly one SSH invocation per deployment: the rsync transport.
rsync "${OPTS[@]}" \
    -e 'ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes' \
    "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/" || die 'rsync failed'
if "$DRY_RUN"; then
    printf 'Dry run complete: %s (server unchanged)\n' "$COMMIT"
    exit 0
fi
curl --noproxy '*' --fail --silent --show-error --connect-timeout 5 --max-time 15 \
    --cacert "$CA_CERT" --output /dev/null "$SITE_URL" || die 'HTTPS health check failed'
printf 'Deployment complete: %s\n' "$COMMIT"
