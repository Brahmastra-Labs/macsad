#!/usr/bin/env bash
set -Eeuo pipefail

readonly TRUSTED_PATH='/usr/bin:/bin'
export PATH="${TRUSTED_PATH}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
readonly EXPECTED_USER='macsad-verifier'
readonly EXPECTED_GROUP='macsad-verifier'
readonly ROLE_FILE='/etc/macsad/firebat2-runner-role'
readonly EXPECTED_ROLE='macsad-firebat2-verifier-v1'
readonly IMAGE_MARKER='/etc/macsad/firebat2-ephemeral-image'
readonly EXPECTED_IMAGE_MARKER='macsad-firebat2-ephemeral-vm-v1'
readonly RUNNER_ROOT='/opt/macsad/actions-runner'
readonly RUNNER_LISTENER='/opt/macsad/actions-runner/bin/Runner.Listener'
readonly RUNNER_SETTINGS='/opt/macsad/actions-runner/.runner'
readonly EXPECTED_RUNNER_VERSION='2.337.0'
readonly RUNNER_LOCK='/etc/macsad/actions-runner-lock.json'
readonly RUNNER_ARCHIVE='/opt/macsad/actions-runner-archives/actions-runner-linux-x64-2.337.0.tar.gz'
readonly EXPECTED_RUNNER_ARCHIVE_SHA256='70920811a4f8ad4328818682bca5c6469c1c942fab52448868071d0063816613'
readonly VIRT_BIN='/usr/bin/systemd-detect-virt'
readonly PYTHON_BIN='/usr/bin/python3'
readonly NODE_BIN='/usr/bin/node'
readonly CHROMIUM_BIN='/usr/bin/chromium'
readonly TIMEOUT_BIN='/usr/bin/timeout'
readonly TEE_BIN='/usr/bin/tee'
readonly EXPECTED_LOGOS_WORKSPACE='/opt/macsad/toolchains/logicaffeine-private'
readonly MINIMUM_AVAILABLE_BYTES=$((20 * 1024 * 1024 * 1024))
readonly MINIMUM_AVAILABLE_MEMORY_KIB=$((4 * 1024 * 1024))

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

root_owned_read_only_path() {
  local path="$1"
  [[ -e "${path}" ]] || die "required path is missing: ${path}"
  local canonical
  canonical="$(realpath -- "${path}")"
  [[ "$(stat -c '%u' -- "${canonical}")" == '0' ]] ||
    die "path is not root-owned: ${path}"
  [[ ! -w "${canonical}" ]] || die "path is writable by the verifier: ${path}"
}

root_owned_immutable_directory_node() {
  local path="$1"
  [[ -d "${path}" && ! -L "${path}" ]] ||
    die "immutable directory is missing or linked: ${path}"
  [[ "$(realpath -- "${path}")" == "${path}" ]] ||
    die "immutable directory resolves outside its exact path: ${path}"
  root_owned_read_only_path "${path}"
  local mode
  mode="$(stat -c '%a' -- "${path}")"
  (( (8#${mode} & 8#022) == 0 )) ||
    die "immutable directory is group/world-writable: ${path}"
}

root_owned_runner_tree() {
  local path="$1"
  root_owned_immutable_directory_node "${path}"
  local diagnostics="${path}/_diag"
  [[ -d "${diagnostics}" && ! -L "${diagnostics}" ]] ||
    die "runner diagnostics directory is missing or linked: ${diagnostics}"
  [[ "$(realpath -- "${diagnostics}")" == "${diagnostics}" ]] ||
    die "runner diagnostics directory resolves outside its exact path"
  [[ "$(stat -c '%U:%a' -- "${diagnostics}")" == "${EXPECTED_USER}:700" ]] ||
    die "runner diagnostics directory must be owned by ${EXPECTED_USER} with mode 0700"
  local unsafe_entry
  unsafe_entry="$(find "${path}" -xdev \
    -path "${diagnostics}" -prune -o \
    ! -type l \( ! -user root -o -perm /022 -o -writable \) -print -quit)"
  [[ -z "${unsafe_entry}" ]] ||
    die "runner distribution contains a non-root owner or writable static entry: ${unsafe_entry}"
  unsafe_entry="$(find "${diagnostics}" -xdev \
    \( -type l -o ! -user "${EXPECTED_USER}" -o -perm /077 \) -print -quit)"
  [[ -z "${unsafe_entry}" ]] ||
    die "runner diagnostics contain a link, foreign owner, or group/world access: ${unsafe_entry}"
}

verify_runner_release_integrity() {
  root_owned_read_only_path "${RUNNER_LOCK}"
  root_owned_read_only_path "${RUNNER_ARCHIVE}"
  root_owned_read_only_path "${PYTHON_BIN}"
  [[ -x "${PYTHON_BIN}" ]] || die 'fixed Python executable is unavailable'
  "${PYTHON_BIN}" - \
    "${RUNNER_LOCK}" \
    "${RUNNER_ARCHIVE}" \
    "${RUNNER_ROOT}" \
    "${EXPECTED_RUNNER_VERSION}" \
    "${EXPECTED_RUNNER_ARCHIVE_SHA256}" <<'PY'
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import sys
import tarfile

lock_path, archive_path, runner_root, version, expected_archive_sha256 = sys.argv[1:]
expected_lock = {
    "schema_version": 1,
    "release": version,
    "platform": "linux-x64",
    "archive_name": f"actions-runner-linux-x64-{version}.tar.gz",
    "source_url": (
        f"https://github.com/actions/runner/releases/download/v{version}/"
        f"actions-runner-linux-x64-{version}.tar.gz"
    ),
    "archive_sha256": expected_archive_sha256,
    "guest_archive_path": archive_path,
    "guest_install_root": runner_root,
    "guest_lock_path": lock_path,
}
actual_lock = json.loads(Path(lock_path).read_text(encoding="utf-8"))
if actual_lock != expected_lock:
    raise SystemExit("root-owned Actions Runner release lock does not match the admitted contract")

def digest_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

actual_archive_sha256 = digest_file(archive_path)
if actual_archive_sha256 != expected_archive_sha256:
    raise SystemExit(
        "Actions Runner archive digest mismatch: "
        f"expected {expected_archive_sha256}, found {actual_archive_sha256}"
    )

root = Path(runner_root)
runtime_files = {".credentials", ".credentials_rsaparams", ".env", ".path", ".runner"}
runtime_trees = {"_diag"}
expected = {}

def normalized_member_name(name):
    while name.startswith("./"):
        name = name[2:]
    name = name.rstrip("/")
    if not name:
        return "."
    candidate = PurePosixPath(name)
    if candidate.is_absolute() or ".." in candidate.parts or str(candidate) != name:
        raise SystemExit(f"unsafe Actions Runner archive member: {name}")
    return name

with tarfile.open(archive_path, mode="r:gz") as archive:
    for member in archive.getmembers():
        name = normalized_member_name(member.name)
        if name in expected:
            raise SystemExit(f"duplicate Actions Runner archive member: {name}")
        if member.isdir():
            kind = "directory"
        elif member.isfile():
            kind = "file"
        elif member.issym():
            kind = "symlink"
        else:
            raise SystemExit(f"unsupported Actions Runner archive member type: {name}")
        expected[name] = (kind, member.mode & 0o7777, member)

    actual_static = {"."}
    for directory, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        relative_directory = Path(directory).relative_to(root)
        if relative_directory == Path("."):
            directory_names[:] = [name for name in directory_names if name not in runtime_trees]
        for name in directory_names + file_names:
            relative = (relative_directory / name).as_posix()
            if relative in runtime_files or relative in runtime_trees:
                continue
            actual_static.add(relative)

    expected_names = set(expected)
    if actual_static != expected_names:
        missing = sorted(expected_names - actual_static)[:5]
        extra = sorted(actual_static - expected_names)[:5]
        raise SystemExit(
            f"Actions Runner extracted tree membership mismatch; missing={missing}, extra={extra}"
        )

    for name in sorted(expected_names):
        kind, expected_mode, member = expected[name]
        candidate = root if name == "." else root / Path(*PurePosixPath(name).parts)
        candidate_stat = candidate.lstat()
        actual_mode = stat.S_IMODE(candidate_stat.st_mode)
        if actual_mode != expected_mode:
            raise SystemExit(
                f"Actions Runner mode mismatch for {name}: expected {expected_mode:o}, found {actual_mode:o}"
            )
        if candidate_stat.st_uid != 0:
            raise SystemExit(f"Actions Runner extracted member is not root-owned: {name}")
        if kind == "directory":
            if not stat.S_ISDIR(candidate_stat.st_mode):
                raise SystemExit(f"Actions Runner directory was replaced: {name}")
        elif kind == "file":
            if not stat.S_ISREG(candidate_stat.st_mode):
                raise SystemExit(f"Actions Runner file was replaced: {name}")
            source = archive.extractfile(member)
            if source is None:
                raise SystemExit(f"Actions Runner archive file cannot be read: {name}")
            digest = hashlib.sha256()
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
            if digest.hexdigest() != digest_file(candidate):
                raise SystemExit(f"Actions Runner file digest mismatch: {name}")
        else:
            if not stat.S_ISLNK(candidate_stat.st_mode):
                raise SystemExit(f"Actions Runner symlink was replaced: {name}")
            if os.readlink(candidate) != member.linkname:
                raise SystemExit(f"Actions Runner symlink target mismatch: {name}")
            resolved = (candidate.parent / member.linkname).resolve(strict=False)
            try:
                resolved.relative_to(root)
            except ValueError:
                raise SystemExit(f"Actions Runner symlink escapes its immutable tree: {name}")
PY
}

assert_unprivileged_process() {
  [[ "$(id -gn)" == "${EXPECTED_GROUP}" && "$(id -nG)" == "${EXPECTED_GROUP}" ]] ||
    die "verifier identity must belong only to the private ${EXPECTED_GROUP} group"
  if ! awk '
    /^Cap(Inh|Prm|Eff|Amb):/ {
      count += 1
      if ($2 !~ /^0+$/) unsafe = 1
    }
    END { exit !(count == 4 && unsafe != 1) }
  ' /proc/self/status; then
    die 'verifier process has a missing or nonzero Linux capability set'
  fi
  grep -Eq '^NoNewPrivs:[[:space:]]+1$' /proc/self/status ||
    die 'verifier process must run with NoNewPrivs=1'
}

main() {
  (($# == 0)) || die 'verify_verifier_host.sh accepts no arguments'
  [[ "$(uname -s)" == 'Linux' ]] || die 'Firebat2 verifier must run on Linux'
  [[ "$(id -u)" -ne 0 && "$(id -un)" == "${EXPECTED_USER}" ]] ||
    die "run as the dedicated ${EXPECTED_USER} identity"
  [[ "${PATH}" == "${TRUSTED_PATH}" ]] || die 'verifier PATH is not the fixed system path'
  assert_unprivileged_process
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    die 'verifier identity has noninteractive sudo'
  fi
  [[ ! -S /var/run/docker.sock || ! -w /var/run/docker.sock ]] ||
    die 'verifier identity can write the Docker socket'

  root_owned_read_only_path "${VIRT_BIN}"
  [[ -x "${VIRT_BIN}" ]] || die 'systemd-detect-virt is unavailable'
  local virtualization
  virtualization="$("${VIRT_BIN}" --vm)"
  [[ "${virtualization}" == 'kvm' || "${virtualization}" == 'qemu' ]] ||
    die "verifier must run inside a disposable KVM/QEMU VM; found ${virtualization}"
  [[ -f "${IMAGE_MARKER}" && ! -L "${IMAGE_MARKER}" ]] ||
    die 'ephemeral verifier image marker is missing or linked'
  [[ "$(cat "${IMAGE_MARKER}")" == "${EXPECTED_IMAGE_MARKER}" ]] ||
    die 'ephemeral verifier image marker has the wrong value'
  root_owned_read_only_path "${IMAGE_MARKER}"

  [[ -f "${ROLE_FILE}" && ! -L "${ROLE_FILE}" ]] || die 'runner role marker is missing or linked'
  [[ "$(cat "${ROLE_FILE}")" == "${EXPECTED_ROLE}" ]] || die 'runner role marker has the wrong value'
  root_owned_read_only_path "${ROLE_FILE}"
  local role_mode
  role_mode="$(stat -c '%a' -- "${ROLE_FILE}")"
  [[ "${role_mode}" == '444' || "${role_mode}" == '644' ]] ||
    die 'runner role marker must have mode 0444 or 0644'

  root_owned_immutable_directory_node '/opt'
  root_owned_immutable_directory_node '/opt/macsad'
  root_owned_immutable_directory_node '/opt/macsad/actions-runner-archives'
  root_owned_immutable_directory_node '/opt/macsad/toolchains'
  root_owned_immutable_directory_node '/etc'
  root_owned_immutable_directory_node '/etc/macsad'
  root_owned_immutable_directory_node '/usr'
  root_owned_immutable_directory_node '/usr/bin'
  [[ -L /bin && "$(realpath -- /bin)" == '/usr/bin' ]] ||
    die '/bin must be the canonical root-owned usrmerge link to /usr/bin'
  root_owned_read_only_path '/bin'
  root_owned_runner_tree "${RUNNER_ROOT}"
  verify_runner_release_integrity
  root_owned_read_only_path "${RUNNER_LISTENER}"
  [[ -x "${RUNNER_LISTENER}" ]] || die 'GitHub runner listener is not executable'
  local runner_version
  runner_version="$("${RUNNER_LISTENER}" --version)"
  [[ "${runner_version}" == "${EXPECTED_RUNNER_VERSION}" ]] ||
    die "GitHub runner must be exactly ${EXPECTED_RUNNER_VERSION}; found ${runner_version}"
  root_owned_read_only_path "${RUNNER_SETTINGS}"
  "${PYTHON_BIN}" - "${RUNNER_SETTINGS}" <<'PY'
import json
import pathlib
import sys

settings = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
get = lambda lower, upper: settings.get(lower, settings.get(upper))
if get("ephemeral", "Ephemeral") is not True:
    raise SystemExit("GitHub runner settings do not prove --ephemeral registration")
if get("disableUpdate", "DisableUpdate") is not True:
    raise SystemExit("GitHub runner settings do not prove --disableupdate registration")
if get("workFolder", "WorkFolder") != "/var/lib/macsad-runner/_work":
    raise SystemExit("GitHub runner work folder is not the disposable VM path")
if get("gitHubUrl", "GitHubUrl") != "https://github.com/Brahmastra-Labs":
    raise SystemExit("GitHub runner is not registered to the Brahmastra-Labs organization")
if get("poolName", "PoolName") != "macsad-firebat2":
    raise SystemExit("GitHub runner is not in the restricted Firebat2 runner group")
PY

  root_owned_read_only_path "${NODE_BIN}"
  [[ -x "${NODE_BIN}" ]] || die 'fixed Node executable is unavailable'
  local node_version
  node_version="$("${NODE_BIN}" --version)"
  [[ "${node_version}" =~ ^v24\.[0-9]+\.[0-9]+$ ]] ||
    die "Firebat2 requires Node 24; found ${node_version}"

  root_owned_read_only_path "${CHROMIUM_BIN}"
  [[ -x "${CHROMIUM_BIN}" ]] || die 'fixed Chromium executable is unavailable'
  "${CHROMIUM_BIN}" --version | grep -Eq '^Chromium [0-9]+\.' ||
    die 'fixed Chromium executable returned an unexpected version'

  root_owned_read_only_path "${TIMEOUT_BIN}"
  [[ -x "${TIMEOUT_BIN}" ]] || die 'fixed timeout executable is unavailable'
  root_owned_read_only_path "${TEE_BIN}"
  [[ -x "${TEE_BIN}" ]] || die 'fixed tee executable is unavailable'

  [[ "${LOGOS_WORKSPACE:-}" == "${EXPECTED_LOGOS_WORKSPACE}" ]] ||
    die "LOGOS_WORKSPACE must equal ${EXPECTED_LOGOS_WORKSPACE}"
  [[ -d "${LOGOS_WORKSPACE}" && ! -L "${LOGOS_WORKSPACE}" ]] ||
    die 'fixed LOGOS workspace is missing or linked'
  [[ "$(realpath -- "${LOGOS_WORKSPACE}")" == "${EXPECTED_LOGOS_WORKSPACE}" ]] ||
    die 'fixed LOGOS workspace resolves elsewhere'
  root_owned_read_only_path "${LOGOS_WORKSPACE}"
  local unsafe_logos_entry
  unsafe_logos_entry="$(find "${LOGOS_WORKSPACE}" -xdev \
    \( -type l -o ! -user root -o -writable \) -print -quit)"
  [[ -z "${unsafe_logos_entry}" ]] ||
    die "LOGOS workspace contains a linked, non-root-owned, or verifier-writable entry: ${unsafe_logos_entry}"
  GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=safe.directory \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_VALUE_0="${LOGOS_WORKSPACE}" \
    HOME=/nonexistent \
    XDG_CONFIG_HOME=/nonexistent \
    "${REPOSITORY_ROOT}/scripts/logos.sh" --version >/dev/null

  [[ -d /var/lib/macsad-runner && ! -L /var/lib/macsad-runner ]] ||
    die 'dedicated runner state directory is missing or linked'
  local available_bytes
  available_bytes="$(df --output=avail -B1 /var/lib/macsad-runner | tail -n 1 | tr -d ' ')"
  [[ "${available_bytes}" =~ ^[0-9]+$ && "${available_bytes}" -ge "${MINIMUM_AVAILABLE_BYTES}" ]] ||
    die 'Firebat2 has less than 20 GiB available for verification'
  local available_memory_kib
  available_memory_kib="$(awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo)"
  [[ "${available_memory_kib}" =~ ^[0-9]+$ && "${available_memory_kib}" -ge "${MINIMUM_AVAILABLE_MEMORY_KIB}" ]] ||
    die 'Firebat2 has less than 4 GiB available memory'

  git -C "${REPOSITORY_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    die 'verification checkout is not a Git worktree'
  [[ -z "$(git -C "${REPOSITORY_ROOT}" status --porcelain --untracked-files=all)" ]] ||
    die 'verification checkout is dirty or contains stale artifacts'
  if [[ -n "${MACSAD_SOURCE_SHA:-}" ]]; then
    [[ "${MACSAD_SOURCE_SHA}" =~ ^[0-9a-f]{40}$ ]] || die 'MACSAD_SOURCE_SHA is invalid'
    [[ "$(git -C "${REPOSITORY_ROOT}" rev-parse --verify HEAD)" == "${MACSAD_SOURCE_SHA}" ]] ||
      die 'verification checkout is stale for the admitted source SHA'
  fi

  printf '%s\n' \
    "Firebat2 verifier host passed for ${EXPECTED_USER}." \
    "Runner ${EXPECTED_RUNNER_VERSION}; ${node_version}; fixed Chromium; exact read-only LOGOS lock."
}

main "$@"
