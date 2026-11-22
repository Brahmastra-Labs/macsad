#!/usr/bin/env bash
# Build the factory's two binaries and pin them.
#
#   largo    — the LOGOS toolchain, built from the local logicaffeine tree (the kernel, the provers,
#              and the std with process.lg, httpclient.lg, s3.lg and the file natives);
#   factory  — macsad/logos/factory compiled by that largo (coordinator, worker, verifier, local).
#
# Mechanical only: this script builds, copies and hashes. Every decision the factory makes lives in
# its LOGOS source. The receipt records exactly what was built — the binaries' SHA-256, the LOGOS
# source tree's identity (HEAD plus a digest of every source file, because the latest LOGOS may be
# uncommitted work), and the factory source digest — so a container can say what it runs.
set -Eeuo pipefail

readonly HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly MACSAD="$(cd -- "${HERE}/../.." && pwd -P)"
readonly LOGOS="${LOGOS_WORKSPACE:-/home/tristen/logicaffeine}"
readonly TARGET="${MACSAD_CARGO_TARGET:-/mnt/build/macsad-target}"
readonly OUT="${HERE}/bin"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
command -v cargo >/dev/null || die 'cargo is required'
command -v sha256sum >/dev/null || die 'sha256sum is required'
[[ -f "${LOGOS}/Cargo.toml" ]] || die "LOGOS_WORKSPACE is not a logicaffeine tree: ${LOGOS}"

free_gb="$(df -BG --output=avail "$(dirname -- "${TARGET}")" | tail -1 | tr -dc '0-9')"
(( free_gb >= 20 )) || die "only ${free_gb}G free under ${TARGET}; refusing to build into a nearly full disk"

mkdir -p "${OUT}"

printf '==> building largo from %s\n' "${LOGOS}"
(cd "${LOGOS}" && CARGO_TARGET_DIR="${TARGET}" cargo build --release -p logicaffeine-cli --bin largo)
install -m 0755 "${TARGET}/release/largo" "${OUT}/largo"

printf '==> building the factory with that largo\n'
(cd "${MACSAD}/logos/factory" && LOGOS_WORKSPACE="${LOGOS}" CARGO_TARGET_DIR="${TARGET}/factory" \
  "${OUT}/largo" build --release)
factory_bin="$(find "${MACSAD}/logos/factory/target/release" -maxdepth 1 -type f -name factory -perm -u+x 2>/dev/null | head -1)"
[[ -n "${factory_bin}" ]] || die 'largo build produced no factory binary'
install -m 0755 "${factory_bin}" "${OUT}/factory"

# The LOGOS source identity: HEAD, and a digest over every tracked-looking source file, because the
# latest LOGOS the factory runs may include work not yet committed.
logos_head="$(cat "${LOGOS}/.git/HEAD" 2>/dev/null || true)"
if [[ "${logos_head}" == ref:* ]]; then
  logos_head="$(cat "${LOGOS}/.git/${logos_head#ref: }" 2>/dev/null || printf 'unknown')"
fi
source_digest() {
  (cd "$1" && find "${@:2}" -type f \( -name '*.rs' -o -name '*.lg' -o -name '*.toml' -o -name '*.lock' \) \
     -not -path '*/target/*' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
}
logos_digest="$(source_digest "${LOGOS}" crates apps Cargo.toml Cargo.lock)"
factory_digest="$(source_digest "${MACSAD}/logos/factory" .)"

cat >"${OUT}/toolchain.receipt.json" <<JSON
{
  "schema": "macsad-factory-toolchain/1",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "largo_sha256": "$(sha256sum "${OUT}/largo" | cut -d' ' -f1)",
  "largo_version": "$("${OUT}/largo" --version | tr -d '\n')",
  "factory_sha256": "$(sha256sum "${OUT}/factory" | cut -d' ' -f1)",
  "logos_head": "${logos_head}",
  "logos_source_sha256": "${logos_digest}",
  "factory_source_sha256": "${factory_digest}"
}
JSON
printf '==> pinned:\n'
cat "${OUT}/toolchain.receipt.json"
