#!/usr/bin/env bash
set -euo pipefail

DIR="./vscode-linux-x64-stable"
OUT_FILE="vscode-version-commit.txt"
MIN_VERSION="1.81.1"

PRODUCT_JSON_PATH="VSCode-linux-x64/resources/app/product.json"

> "${OUT_FILE}"

version_ge() {
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" == "$1" ]]
}

for file in "${DIR}"/vscode-*-linux-x64.tar.gz; do
    [[ -f "$file" ]] || continue

    # 1. 从文件名提取版本号
    version="$(basename "$file" | sed -E 's/^vscode-([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/')"

    # 防御性检查
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        continue
    fi

    # 2. 版本过滤：只要 >= 1.81.1
    if ! version_ge "$version" "$MIN_VERSION"; then
        continue
    fi

    # 3. 读取 product.json
    if ! json="$(tar -xOzf "$file" "$PRODUCT_JSON_PATH" 2>/dev/null)"; then
        continue
    fi

    # 4. 提取 commit-id
    commit="$(jq -r '.commit // empty' <<< "$json")"
    [[ -n "$commit" && "$commit" != "null" ]] || continue

    # 5. 输出
    printf "%s\t%s\n" "$version" "$commit" >> "$OUT_FILE"
done

echo "[DONE] Versions >= ${MIN_VERSION} written to ${OUT_FILE}"
