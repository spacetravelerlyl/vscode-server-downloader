#!/usr/bin/env bash
set -euo pipefail

DIR="./vscode-linux-x64-stable"
OUT_FILE="vscode-version-commit.txt"

PRODUCT_JSON_PATH="VSCode-linux-x64/resources/app/product.json"

> "${OUT_FILE}"

for file in "${DIR}"/vscode-*-linux-x64.tar.gz; do
    [[ -f "$file" ]] || continue

    # 1. 从文件名提取版本号
    # vscode-1.95.3-linux-x64.tar.gz
    version="$(basename "$file" | sed -E 's/^vscode-([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/')"

    # 防御性校验
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "[SKIP] Invalid version from filename: $file"
        continue
    fi

    # 2. 从 tar.gz 中读取 product.json
    if ! json="$(tar -xOzf "$file" "$PRODUCT_JSON_PATH" 2>/dev/null)"; then
        echo "[WARN] product.json not found in $file"
        continue
    fi

    # 3. 提取 commit-id
    commit="$(jq -r '.commit // empty' <<< "$json")"

    if [[ -z "$commit" || "$commit" == "null" ]]; then
        echo "[WARN] commit not found for version $version"
        continue
    fi

    # 4. 写入结果
    printf "%s\t%s\n" "$version" "$commit" >> "$OUT_FILE"
	break
done

echo "[DONE] Output written to ${OUT_FILE}"
