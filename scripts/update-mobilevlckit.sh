#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${MOBILEVLCKIT_BASE_URL:-https://download.videolan.org/pub/cocoapods/prod/}"
REQUESTED_VERSION="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/update-mobilevlckit.sh [latest|VERSION]

Examples:
  scripts/update-mobilevlckit.sh latest
  scripts/update-mobilevlckit.sh 3.7.3

Environment:
  MOBILEVLCKIT_BASE_URL  Override VideoLAN binary directory.
USAGE
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing required tool: $1" >&2
    exit 1
  fi
}

if [[ "${REQUESTED_VERSION}" == "-h" || "${REQUESTED_VERSION}" == "--help" ]]; then
  usage
  exit 0
fi

require_tool curl
require_tool ditto
require_tool lipo
require_tool plutil
require_tool python3
require_tool codesign
require_tool xcodebuild
require_tool xcrun

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mobilevlckit-update.XXXXXX")"
cleanup() {
  if [[ "${KEEP_MOBILEVLCKIT_UPDATE_WORKDIR:-0}" == "1" ]]; then
    echo "Keeping work directory: ${WORK_DIR}"
  else
    rm -rf "${WORK_DIR}"
  fi
}
trap cleanup EXIT

INDEX_FILE="${WORK_DIR}/index.html"
curl -fsSL "${BASE_URL}" -o "${INDEX_FILE}"

read -r RESOLVED_VERSION ARCHIVE_NAME < <(
  python3 - "${INDEX_FILE}" "${REQUESTED_VERSION}" <<'PY'
import re
import sys

index_path, requested = sys.argv[1], sys.argv[2]
html = open(index_path, encoding="utf-8", errors="replace").read()
matches = re.findall(r'href="(MobileVLCKit-([0-9]+(?:\.[0-9]+)*(?:[ab][0-9]+)?)-[^"]+\.tar\.xz)"', html)
if not matches:
    raise SystemExit("No MobileVLCKit tarballs found in index")

items = [(version, filename) for filename, version in matches]

def key(version):
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)*)(?:([ab])([0-9]+))?", version)
    if not match:
        return ((), -1, -1)
    numbers = [int(part) for part in match.group(1).split(".")]
    while len(numbers) < 4:
        numbers.append(0)
    prerelease_kind = match.group(2)
    prerelease_number = int(match.group(3) or 0)
    prerelease_rank = 2 if prerelease_kind is None else {"a": 0, "b": 1}[prerelease_kind]
    return (tuple(numbers), prerelease_rank, prerelease_number)

if requested == "latest":
    stable = [(version, filename) for version, filename in items if re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", version)]
    version, filename = max(stable or items, key=lambda item: key(item[0]))
else:
    exact = [(version, filename) for version, filename in items if version == requested]
    if not exact:
        available = ", ".join(sorted({version for version, _ in items}, key=key)[-10:])
        raise SystemExit(f"MobileVLCKit {requested} not found. Recent available versions: {available}")
    version, filename = exact[-1]

print(version, filename)
PY
)

ARCHIVE_URL="${BASE_URL%/}/${ARCHIVE_NAME}"
ARCHIVE_PATH="${WORK_DIR}/${ARCHIVE_NAME}"
EXTRACT_DIR="${WORK_DIR}/extract"
BUILD_DIR="${WORK_DIR}/build"
OUTPUT_DIR="${WORK_DIR}/output"

echo "Resolved MobileVLCKit ${RESOLVED_VERSION}"
echo "Downloading ${ARCHIVE_URL}"
curl -fL --retry 3 --retry-delay 2 --show-error --progress-bar -o "${ARCHIVE_PATH}" "${ARCHIVE_URL}"

mkdir -p "${EXTRACT_DIR}" "${BUILD_DIR}/device" "${BUILD_DIR}/simulator" "${OUTPUT_DIR}"
tar -xf "${ARCHIVE_PATH}" -C "${EXTRACT_DIR}"

SOURCE_XCFRAMEWORK="$(find "${EXTRACT_DIR}" -maxdepth 4 -type d -name 'MobileVLCKit.xcframework' -print -quit)"
if [[ -z "${SOURCE_XCFRAMEWORK}" ]]; then
  echo "error: MobileVLCKit.xcframework not found in archive" >&2
  exit 1
fi

xcframework_identifier() {
  local variant="$1"
  python3 - "${SOURCE_XCFRAMEWORK}" "${variant}" <<'PY'
import pathlib
import plistlib
import sys

root = pathlib.Path(sys.argv[1])
variant = sys.argv[2]
data = plistlib.loads((root / "Info.plist").read_bytes())
want_simulator = variant == "simulator"

for library in data["AvailableLibraries"]:
    is_ios = library.get("SupportedPlatform") == "ios"
    is_simulator = library.get("SupportedPlatformVariant") == "simulator"
    if is_ios and is_simulator == want_simulator:
        print(library["LibraryIdentifier"])
        raise SystemExit(0)

raise SystemExit(f"No iOS {variant} slice found")
PY
}

DEVICE_ID="$(xcframework_identifier device)"
SIMULATOR_ID="$(xcframework_identifier simulator)"
DEVICE_FRAMEWORK="${BUILD_DIR}/device/MobileVLCKit.framework"
SIMULATOR_FRAMEWORK="${BUILD_DIR}/simulator/MobileVLCKit.framework"

ditto "${SOURCE_XCFRAMEWORK}/${DEVICE_ID}/MobileVLCKit.framework" "${DEVICE_FRAMEWORK}"
ditto "${SOURCE_XCFRAMEWORK}/${SIMULATOR_ID}/MobileVLCKit.framework" "${SIMULATOR_FRAMEWORK}"

remove_arches() {
  local binary="$1"
  shift
  local arch
  for arch in "$@"; do
    if lipo -archs "${binary}" | tr ' ' '\n' | grep -Fx "${arch}" >/dev/null; then
      local tmp="${binary}.tmp"
      lipo "${binary}" -remove "${arch}" -output "${tmp}"
      mv "${tmp}" "${binary}"
    fi
  done
}

strip_signature() {
  local framework="$1"
  local binary="${framework}/MobileVLCKit"
  rm -rf "${framework}/_CodeSignature"
  codesign --remove-signature "${binary}" >/dev/null 2>&1 || true
  codesign --remove-signature "${framework}" >/dev/null 2>&1 || true
}

remove_arches "${DEVICE_FRAMEWORK}/MobileVLCKit" armv7 armv7s
remove_arches "${SIMULATOR_FRAMEWORK}/MobileVLCKit" i386
strip_signature "${DEVICE_FRAMEWORK}"
strip_signature "${SIMULATOR_FRAMEWORK}"

xcodebuild -create-xcframework \
  -framework "${DEVICE_FRAMEWORK}" \
  -framework "${SIMULATOR_FRAMEWORK}" \
  -output "${OUTPUT_DIR}/MobileVLCKit.xcframework" >/dev/null

device_arches="$(lipo -archs "${OUTPUT_DIR}/MobileVLCKit.xcframework/ios-arm64/MobileVLCKit.framework/MobileVLCKit")"
simulator_arches="$(lipo -archs "${OUTPUT_DIR}/MobileVLCKit.xcframework/ios-arm64_x86_64-simulator/MobileVLCKit.framework/MobileVLCKit" | tr ' ' '\n' | sort | xargs)"
if [[ "${device_arches}" != "arm64" ]]; then
  echo "error: unexpected device architectures: ${device_arches}" >&2
  exit 1
fi
if [[ "${simulator_arches}" != "arm64 x86_64" ]]; then
  echo "error: unexpected simulator architectures: ${simulator_arches}" >&2
  exit 1
fi

rm -rf "${ROOT_DIR}/MobileVLCKit.xcframework"
ditto "${OUTPUT_DIR}/MobileVLCKit.xcframework" "${ROOT_DIR}/MobileVLCKit.xcframework"

python3 - "${ROOT_DIR}/README.md" "${RESOLVED_VERSION}" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
if not path.exists():
    raise SystemExit(0)

text = path.read_text()
updated = re.sub(
    r"tracks \*\*MobileVLCKit [^*]+\*\*",
    f"tracks **MobileVLCKit {version}**",
    text,
    count=1,
)
if updated != text:
    path.write_text(updated)
PY

echo "Updated ${ROOT_DIR}/MobileVLCKit.xcframework to MobileVLCKit ${RESOLVED_VERSION}"
lipo -info "${ROOT_DIR}/MobileVLCKit.xcframework/ios-arm64/MobileVLCKit.framework/MobileVLCKit"
lipo -info "${ROOT_DIR}/MobileVLCKit.xcframework/ios-arm64_x86_64-simulator/MobileVLCKit.framework/MobileVLCKit"
plutil -p "${ROOT_DIR}/MobileVLCKit.xcframework/Info.plist" >/dev/null
xcrun dwarfdump --uuid "${ROOT_DIR}/MobileVLCKit.xcframework/ios-arm64/MobileVLCKit.framework/MobileVLCKit" \
  "${ROOT_DIR}/MobileVLCKit.xcframework/ios-arm64_x86_64-simulator/MobileVLCKit.framework/MobileVLCKit"
