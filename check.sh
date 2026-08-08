#!/usr/bin/env bash
set -euo pipefail

scripts=(
    download_all_release.sh
    get_product_commitid.sh
    vscode-server-downloader.sh
    vscode_version_commit.sh
)

echo "[INFO] Running bash syntax checks..."
bash -n "${scripts[@]}"

if command -v shellcheck >/dev/null 2>&1; then
    echo "[INFO] Running shellcheck..."
    shellcheck "${scripts[@]}"
else
    echo "[WARN] shellcheck not found, skipped"
fi

echo "[INFO] Checking version commit map..."
bash -c 'source ./vscode_version_commit.sh && declare -p VSCODE_VERSION_COMMIT >/dev/null'

echo "[INFO] Checking version lookup..."
bash ./vscode-server-downloader.sh --check-version 1.108.0 >/dev/null

echo "[INFO] Checking commit fetcher help..."
bash ./get_product_commitid.sh --help >/dev/null

echo "[DONE] Checks passed."
