#!/bin/bash

VERSION=$(curl -s https://update.code.visualstudio.com/api/releases/stable)
echo "$VERSION"


# code-618725e675656290ba4da6fe2d29f8fa1d4e3622
# code-bf9252a2fb45be6893dd8870c0bf37e2e1766d61

./vscode-server-downloader.sh -d 618725e675656290ba4da6fe2d29f8fa1d4e3622
./vscode-server-downloader.sh -d bf9252a2fb45be6893dd8870c0bf37e2e1766d61
wget --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" --max-redirect=10 \
  --no-check-certificate -O vscode-cli-alpine-x64.tar.gz "https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64&version=1.106.3"