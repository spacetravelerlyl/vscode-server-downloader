#!/usr/bin/env bash
set -euo pipefail

API_URL="https://update.code.visualstudio.com/api/releases/stable"
BASE_URL="https://update.code.visualstudio.com"
PLATFORM="linux-x64"
CHANNEL="stable"

OUT_DIR="./vscode-linux-x64-stable"
COMMIT_MAP_FILE="./vscode_version_commit.sh"
TMP_JSON="$(mktemp)"
FORCE=0
MIN_VERSION="1.81.1"
PARALLEL=1
SLEEP_MIN=0
SLEEP_MAX=0

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  -f, --force          Download versions even when commit mapping already exists
  --min-version <ver>  Minimum version to process (default: ${MIN_VERSION})
  --parallel <n>       Number of concurrent downloads (default: ${PARALLEL})
  --sleep-min <sec>    Minimum delay after each download task (default: ${SLEEP_MIN})
  --sleep-max <sec>    Maximum delay after each download task (default: ${SLEEP_MAX})
EOF
}

require_value() {
    local opt="$1" val="${2:-}"
    if [[ -z "$val" || "$val" == -* ]]; then
        echo "[ERR] $opt requires a value" >&2
        usage
        exit 1
    fi
}

require_uint() {
    local opt="$1" val="$2"
    if [[ ! "$val" =~ ^[0-9]+$ ]]; then
        echo "[ERR] $opt requires a non-negative integer" >&2
        usage
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE=1
            shift
            ;;
        --min-version)
            require_value "$1" "${2:-}"
            MIN_VERSION="$2"
            shift 2
            ;;
        --parallel)
            require_value "$1" "${2:-}"
            require_uint "$1" "$2"
            PARALLEL="$2"
            shift 2
            ;;
        --sleep-min)
            require_value "$1" "${2:-}"
            require_uint "$1" "$2"
            SLEEP_MIN="$2"
            shift 2
            ;;
        --sleep-max)
            require_value "$1" "${2:-}"
            require_uint "$1" "$2"
            SLEEP_MAX="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

if [[ "$PARALLEL" -lt 1 ]]; then
    echo "[ERR] --parallel must be greater than 0" >&2
    exit 1
fi

if [[ "$SLEEP_MAX" -lt "$SLEEP_MIN" ]]; then
    echo "[ERR] --sleep-max must be greater than or equal to --sleep-min" >&2
    exit 1
fi

trap 'rm -f "${TMP_JSON}"' EXIT

declare -A VSCODE_VERSION_COMMIT=()
if [[ -f "$COMMIT_MAP_FILE" && "$FORCE" -eq 0 ]]; then
    # shellcheck source=/dev/null
    source "$COMMIT_MAP_FILE"
fi

mkdir -p "${OUT_DIR}"

download_file() {
    local target="$1" url="$2" tmp_target
    tmp_target="${target}.tmp"

    rm -f "$tmp_target"

    if command -v curl >/dev/null 2>&1; then
        if curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 -o "$tmp_target" "$url"; then
            mv "$tmp_target" "$target"
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --show-progress --tries=3 --timeout=10 -O "$tmp_target" "$url"; then
            mv "$tmp_target" "$target"
            return 0
        fi
    else
        echo "[ERR] Neither curl nor wget is available" >&2
        return 1
    fi

    rm -f "$tmp_target"
    return 1
}

sleep_between_tasks() {
    local delay

    if [[ "$SLEEP_MAX" -eq 0 ]]; then
        return
    fi

    if [[ "$SLEEP_MAX" -eq "$SLEEP_MIN" ]]; then
        delay="$SLEEP_MAX"
    else
        delay=$((RANDOM % (SLEEP_MAX - SLEEP_MIN + 1) + SLEEP_MIN))
    fi

    sleep "$delay"
}

download_version() {
    local v="$1" url out_file

    echo "[INFO] Processing version ${v}"

    if [[ "$FORCE" -eq 0 && -n "${VSCODE_VERSION_COMMIT[$v]:-}" ]]; then
        echo "  [SKIP] Commit mapping exists: ${v} => ${VSCODE_VERSION_COMMIT[$v]}"
        return 0
    fi

    url="${BASE_URL}/${v}/${PLATFORM}/${CHANNEL}"
    out_file="${OUT_DIR}/vscode-${v}-${PLATFORM}.tar.gz"

    if [[ "$FORCE" -eq 0 && -f "${out_file}" ]]; then
        echo "  [SKIP] Already exists: ${out_file}"
        return 0
    fi

    echo "  [DOWN] ${url}"
    if download_file "${out_file}" "${url}"; then
        echo "  [OK] Saved to ${out_file}"
    else
        echo "  [FAIL] Download failed for version ${v}"
        return 1
    fi

    sleep_between_tasks
}

echo "[INFO] Fetching VS Code stable version list..."
download_file "${TMP_JSON}" "${API_URL}"

echo "[INFO] Parsing versions..."
# mapfile -t VERSIONS < <(jq -r '.[]' "${TMP_JSON}")
# 改为只下载 1.81.1 之后的版本

mapfile -t VERSIONS < <(
  jq -r --arg min "$MIN_VERSION" '
    .[]
    | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
    | select(
        (split(".") | map(tonumber))
        >=
        ($min | split(".") | map(tonumber))
      )
  ' "${TMP_JSON}"
)

echo "[INFO] Total versions: ${#VERSIONS[@]}"
echo "[INFO] Existing commit mappings: ${#VSCODE_VERSION_COMMIT[@]}"
echo "[INFO] Force download: ${FORCE}"
echo "[INFO] Parallel downloads: ${PARALLEL}"
echo "[INFO] Sleep range: ${SLEEP_MIN}-${SLEEP_MAX}s"
echo

running=0
failed=0
pids=()

for v in "${VERSIONS[@]}"; do
    if [[ "$PARALLEL" -eq 1 ]]; then
        download_version "$v" || failed=1
        echo
        continue
    fi

    download_version "$v" &
    pids+=("$!")
    running=$((running + 1))

    if [[ "$running" -ge "$PARALLEL" ]]; then
        for pid in "${pids[@]}"; do
            if ! wait "$pid"; then
                failed=1
            fi
        done
        pids=()
        running=0
    fi
done

for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
        failed=1
    fi
done

if [[ "$failed" -ne 0 ]]; then
    echo "[DONE] All versions processed with failures."
    exit 1
fi

echo "[DONE] All versions processed."
