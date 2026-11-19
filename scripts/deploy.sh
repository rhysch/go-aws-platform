#!/usr/bin/env bash
set -Eeuo pipefail
# Called as root by AWS Systems Manager after the release archive is verified.
[[ $EUID -eq 0 ]] || { echo "Run through SSM as root" >&2; exit 1; }
release_sha=${1:?full commit SHA required}
[[ $release_sha =~ ^[a-f0-9]{40}$ ]] || { echo "Invalid release SHA" >&2; exit 1; }
exec 9>/var/lock/go-aws-platform-deploy.lock
flock -w 30 9 || { echo "Another deployment holds the lock" >&2; exit 1; }
source /etc/go-aws-platform/host.env
base=/opt/go-aws-platform
release="$base/releases/$release_sha"
[[ -f "$release/compose.aws.yaml" && -f "$release/Caddyfile" ]] || exit 1
printf 'RELEASE_SHA=%s\nIMAGE=%s:%s\n' "$release_sha" "$IMAGE_REPOSITORY" "$release_sha" > "$release/release.env"
previous=$(readlink -f "$base/current" || true)
compose() {
    docker compose --project-name go-aws-platform \
      --env-file /etc/go-aws-platform/host.env --env-file "$1/release.env" \
      -f "$1/compose.aws.yaml" "${@:2}"
}
verify() {
    local expected=$1
    for ((attempt = 1; attempt <= 30; attempt++)); do
        if curl -fsS --connect-timeout 3 --max-time 5 http://127.0.0.1:8080/version \
          | jq -e --arg expected "$expected" '.version == $expected' >/dev/null; then return 0; fi
        sleep 2
    done
    return 1
}
failed() {
    local result=$?
    trap - ERR
    echo "Release failed; collecting diagnostics" >&2
    compose "$release" ps || true
    compose "$release" logs --tail=50 || true
    if [[ -n "$previous" && -f "$previous/release.env" ]]; then
        echo "Restoring previous release: $previous" >&2
        if compose "$previous" up -d --wait --wait-timeout 120; then
            echo "Previous containers restored; inspect public endpoint before closing the incident" >&2
        else
            echo "ROLLBACK FAILED: inspect SSM and CloudWatch immediately" >&2
        fi
    else
        echo "No previous release exists; manual recovery required" >&2
    fi
    exit "$result"
}
trap failed ERR
compose "$release" pull
compose "$release" run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
compose "$release" up -d --wait --wait-timeout 120
verify "$release_sha"
# DNS must already target this instance. TLS is verified; never use curl -k.
curl -fsS --retry 12 --retry-delay 5 --retry-all-errors --connect-timeout 5 --max-time 10 \
  "https://$DOMAIN/version" | jq -e --arg expected "$release_sha" '.version == $expected' >/dev/null
ln -sfn "$release" "$base/current.next"
mv -Tf "$base/current.next" "$base/current"
trap - ERR
echo "Release $release_sha verified and marked current"
