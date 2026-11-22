#!/usr/bin/env bash
# Build the factory's two binaries and pin them.
#
#   largo    — the LOGOS toolchain, built from the PUBLIC logicaffeine repository at the revision
#              ops/factory/logos.pin names (the kernel, the provers and the std the factory needs:
#              process.lg, httpclient.lg, s3.lg and the file natives);
#   factory  — macsad/logos/factory compiled by that largo (coordinator, worker, verifier, local).
#
# Mechanical only: this script fetches, builds, copies and hashes. Every decision the factory makes
# lives in its LOGOS source. The receipt records exactly what was built — the binaries' SHA-256, the
# public LOGOS revision, and the factory source digest — so a container can say what it runs.
#
# LOGOS_WORKSPACE=<checkout> builds from an existing checkout instead (development only); the receipt
# then records that checkout's source digest and marks the build as unpinned.
set -Eeuo pipefail

readonly HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly MACSAD="$(cd -- "${HERE}/../.." && pwd -P)"
readonly REPO="${MACSAD_LOGOS_REPO:-https://github.com/Brahmastra-Labs/logicaffeine.git}"
readonly TARGET="${MACSAD_CARGO_TARGET:-${MACSAD}/.runtime/factory/target}"
readonly OUT="${HERE}/bin"
readonly REQUIRED_STD=(process.lg httpclient.lg s3.lg file.lg)

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
command -v cargo >/dev/null || die 'cargo is required'
command -v sha256sum >/dev/null || die 'sha256sum is required'

if [[ -n "${LOGOS_WORKSPACE:-}" ]]; then
  readonly LOGOS="${LOGOS_WORKSPACE}"
  readonly PINNED=false
  logos_rev='unpinned-local-checkout'
else
  logos_rev="$(tr -d '[:space:]' <"${HERE}/logos.pin")"
  [[ "${logos_rev}" =~ ^[0-9a-f]{40}$ ]] || die 'ops/factory/logos.pin must hold one 40-hex public commit'
  readonly LOGOS="${MACSAD}/.runtime/factory/logicaffeine-${logos_rev}"
  readonly PINNED=true
  if [[ ! -d "${LOGOS}/.git" ]]; then
    printf '==> fetching public LOGOS %s at %s\n' "${REPO}" "${logos_rev}"
    git init -q "${LOGOS}"
    git -C "${LOGOS}" fetch -q --depth 1 "${REPO}" "${logos_rev}"
    git -C "${LOGOS}" checkout -q --detach FETCH_HEAD
  fi
  [[ "$(git -C "${LOGOS}" rev-parse HEAD)" == "${logos_rev}" ]] || die "checkout is not ${logos_rev}"
  [[ -z "$(git -C "${LOGOS}" status --porcelain)" ]] || die "the pinned checkout ${LOGOS} has local changes"
fi
[[ -f "${LOGOS}/Cargo.toml" ]] || die "not a logicaffeine tree: ${LOGOS}"
for module in "${REQUIRED_STD[@]}"; do
  [[ -f "${LOGOS}/crates/logicaffeine_compile/assets/std/${module}" ]] ||
    die "LOGOS ${logos_rev} lacks std/${module}; publish it to the public repository and update ops/factory/logos.pin"
done

mkdir -p "${OUT}" "${TARGET}"
free_gb="$(df -BG --output=avail "${TARGET}" | tail -1 | tr -dc '0-9')"
(( free_gb >= 20 )) || die "only ${free_gb}G free under ${TARGET}; refusing to build into a nearly full disk"

printf '==> building largo\n'
(cd "${LOGOS}" && CARGO_TARGET_DIR="${TARGET}" cargo build --release -p logicaffeine-cli --bin largo)
install -m 0755 "${TARGET}/release/largo" "${OUT}/largo"

printf '==> building the factory with that largo\n'
(cd "${MACSAD}/logos/factory" && LOGOS_WORKSPACE="${LOGOS}" CARGO_TARGET_DIR="${TARGET}/factory" \
  "${OUT}/largo" build --release)
factory_bin="$(find "${MACSAD}/logos/factory/target/release" -maxdepth 1 -type f -name factory -perm -u+x 2>/dev/null | head -1)"
[[ -n "${factory_bin}" ]] || die 'largo build produced no factory binary'
install -m 0755 "${factory_bin}" "${OUT}/factory"

source_digest() {
  (cd "$1" && find "${@:2}" -type f \( -name '*.rs' -o -name '*.lg' -o -name '*.toml' -o -name '*.lock' \) \
     -not -path '*/target/*' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
}

cat >"${OUT}/toolchain.receipt.json" <<JSON
{
  "schema": "macsad-factory-toolchain/1",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "logos_repository": "${REPO}",
  "logos_revision": "${logos_rev}",
  "logos_pinned": ${PINNED},
  "logos_source_sha256": "$(source_digest "${LOGOS}" crates apps Cargo.toml Cargo.lock)",
  "largo_sha256": "$(sha256sum "${OUT}/largo" | cut -d' ' -f1)",
  "largo_version": "$("${OUT}/largo" --version | tr -d '\n')",
  "factory_sha256": "$(sha256sum "${OUT}/factory" | cut -d' ' -f1)",
  "factory_source_sha256": "$(source_digest "${MACSAD}/logos/factory" .)"
}
JSON
printf '==> pinned:\n'
cat "${OUT}/toolchain.receipt.json"
