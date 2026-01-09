#!/usr/bin/env bash
set -euo pipefail

# ========= 可配置项 =========
DIR="./vscode-linux-x64-stable"
OUT_FILE="vscode-version-commit.txt"
MIN_VERSION="1.81.1"

PRODUCT_JSON_PATH="VSCode-linux-x64/resources/app/product.json"
# ===========================

> "${OUT_FILE}"

# 语义版本比较：$1 >= $2 ?
version_ge() {
    local IFS=.
    local v1=($1)
    local v2=($2)
    local i

    for ((i=0; i<3; i++)); do
        ((10#${v1[i]} > 10#${v2[i]})) && return 0
        ((10#${v1[i]} < 10#${v2[i]})) && return 1
    done
    return 0
}

echo "[INFO] Scanning directory: ${DIR}"
echo "[INFO] Minimum version: ${MIN_VERSION}"
echo

for file in "${DIR}"/vscode-*-linux-x64.tar.gz; do
    [[ -f "$file" ]] || continue

    # 从文件名提取版本号
    version="$(basename "$file" | sed -E 's/^vscode-([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/')"

    # 严格校验版本格式
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "[SKIP] Invalid version format: $file"
        continue
    fi

    # 版本过滤
    if ! version_ge "$version" "$MIN_VERSION"; then
        continue
    fi

    # 读取 product.json
    if ! json="$(tar -xOzf "$file" "$PRODUCT_JSON_PATH" 2>/dev/null)"; then
        echo "[WARN] product.json not found: $file"
        continue
    fi

    # 提取 commit-id
    commit="$(jq -r '.commit // empty' <<< "$json")"
    if [[ -z "$commit" || "$commit" == "null" ]]; then
        echo "[WARN] commit missing for version $version"
        continue
    fi

    printf "%s\t%s\n" "$version" "$commit" >> "$OUT_FILE"
done

echo
echo "[DONE] Index written to ${OUT_FILE}"
