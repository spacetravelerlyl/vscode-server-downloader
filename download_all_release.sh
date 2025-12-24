#!/usr/bin/env bash
set -euo pipefail

API_URL="https://update.code.visualstudio.com/api/releases/stable"
BASE_URL="https://update.code.visualstudio.com"
PLATFORM="linux-x64"
CHANNEL="stable"

OUT_DIR="./vscode-linux-x64-stable"
TMP_JSON="$(mktemp)"

mkdir -p "${OUT_DIR}"

echo "[INFO] Fetching VS Code stable version list..."
curl -fsSL "${API_URL}" -o "${TMP_JSON}"

echo "[INFO] Parsing versions..."
mapfile -t VERSIONS < <(jq -r '.[]' "${TMP_JSON}")

echo "[INFO] Total versions: ${#VERSIONS[@]}"
echo

for v in "${VERSIONS[@]}"; do
    echo "[INFO] Processing version ${v}"

    url="${BASE_URL}/${v}/${PLATFORM}/${CHANNEL}"
    out_file="${OUT_DIR}/vscode-${v}-${PLATFORM}.tar.gz"

    if [[ -f "${out_file}" ]]; then
        echo "  [SKIP] Already exists: ${out_file}"
        continue
    fi

    echo "  [DOWN] ${url}"
    if curl -fL --retry 3 --retry-delay 2 -o "${out_file}.tmp" "${url}"; then
        mv "${out_file}.tmp" "${out_file}"
        echo "  [OK] Saved to ${out_file}"
    else
        echo "  [FAIL] Download failed for version ${v}"
        rm -f "${out_file}.tmp"
    fi

    echo
done

rm -f "${TMP_JSON}"
echo "[DONE] All versions processed."
