#!/usr/bin/env bash
# Create the factory stack's local credentials once. Values are generated here and written with mode
# 0600 under .runtime/factory/secrets/; they are never printed, logged or committed. An existing file is
# kept, so running this again never rotates a credential behind a running database's back.
#
# Two files hold credentials a human brings rather than generates, and start empty:
#   cloudflare_tunnel_token  — the token of the macsad.com tunnel (Cloudflare Zero Trust → Tunnels);
#   macsad_r2_credentials    — `ACCESS_KEY_ID:SECRET_ACCESS_KEY` of an R2 API token scoped to one bucket.
# Paste them with an editor; the stack runs without either (no public edge, artifacts kept locally).
set -Eeuo pipefail

readonly HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly DIR="${HERE}/../../.runtime/factory/secrets"
umask 077
mkdir -p "${DIR}"

hex64() { od -An -N32 -tx1 /dev/urandom | tr -d ' \n'; }

for name in postgres_superuser_password macsad_deployer_password macsad_runtime_password macsad_viewer_password macsad_verifier_key; do
  if [[ ! -s "${DIR}/${name}" ]]; then
    hex64 >"${DIR}/${name}"
    printf 'created %s\n' "${name}"
  else
    printf 'kept    %s\n' "${name}"
  fi
done
for name in cloudflare_tunnel_token macsad_r2_credentials; do
  [[ -e "${DIR}/${name}" ]] || : >"${DIR}/${name}"
  if [[ -s "${DIR}/${name}" ]]; then printf 'present %s\n' "${name}"; else printf 'empty   %s (optional)\n' "${name}"; fi
done
