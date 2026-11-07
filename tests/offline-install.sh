#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
commit=0123456789012345678901234567890123456789
root="$work/install root"
mkdir -p "$work/payload" "$work/source/server/bin"
printf '#!/bin/sh\nexit 99\n' > "$work/payload/code-$commit"
printf '#!/bin/sh\nexit 0\n' > "$work/source/server/bin/code-server"
cp "$work/source/server/bin/code-server" "$work/source/server/node"
chmod +x "$work/source/server/bin/code-server" "$work/source/server/node"
tar czf "$work/payload/vscode-server-linux-x64-$commit.tar.gz" -C "$work/source" server
cd "$work/payload"
install_server() { bash "$repo/vscode-server-downloader.sh" -i --install-dir "$root" "$@"; }
server="$root/cli/servers/Stable-$commit/server"
# A leftover CLI from Remote-SSH must not prevent Server installation.
mkdir -p "$root"
cp "code-$commit" "$root/"
chmod +x "$root/code-$commit"
printf '# existing CLI\n' >> "$root/code-$commit"
cp "$root/code-$commit" "$work/existing-cli"
old_commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
mkdir -p "$root/bin/$old_commit/bin" "$root/cli/servers/Stable-$old_commit/server/bin" "$root/data" "$root/extensions"
printf old > "$root/bin/$old_commit/bin/code-server"
printf old > "$root/cli/servers/Stable-$old_commit/server/bin/code-server"
printf old > "$root/code-$old_commit"
printf settings > "$root/data/settings.json"
printf extension > "$root/extensions/installed"
printf '["Stable-%s"]' "$old_commit" > "$root/cli/servers/lru.json"
# Preserve even an existing legacy path for the incoming commit.
mkdir -p "$root/bin/$commit"
printf legacy > "$root/bin/$commit/marker"
snapshot_old() {
    sha256sum "$root/bin/$old_commit/bin/code-server" \
        "$root/cli/servers/Stable-$old_commit/server/bin/code-server" \
        "$root/code-$old_commit" "$root/data/settings.json" \
        "$root/extensions/installed" "$root/cli/servers/lru.json" "$root/bin/$commit/marker"
}
snapshot_old > "$work/before"
install_server
test -x "$server/bin/code-server"
test -x "$server/node"
test -x "$root/code-$commit"
cmp "$work/existing-cli" "$root/code-$commit"
printf keep > "$server/marker"
install_server
test -f "$server/marker"
# Preserve an incomplete installation unless repair is explicitly requested.
rm "$server/node"
if install_server; then
    echo 'Incomplete installation unexpectedly overwritten' >&2
    exit 1
fi
test -f "$server/marker"
test ! -e "$server/node"
install_server --force
test -x "$server/node"
install_server --force
# Failed extraction must leave the installed Server intact.
printf invalid > "vscode-server-linux-x64-$commit.tar.gz"
if install_server --force; then
    echo 'Invalid payload unexpectedly succeeded' >&2
    exit 1
fi
test -x "$server/node"
# Reject mismatched payloads before writing to the target.
mv "vscode-server-linux-x64-$commit.tar.gz" vscode-server-linux-x64-wrong.tar.gz
if install_server --force; then
    echo 'Mismatched payload unexpectedly succeeded' >&2
    exit 1
fi
snapshot_old > "$work/after"
cmp "$work/before" "$work/after"
mv vscode-server-linux-x64-wrong.tar.gz "vscode-server-linux-x64-$commit.tar.gz"
# Even --force must not follow a version-specific link into an old install.
mv "$server" "${server}.saved"
ln -s "$root/cli/servers/Stable-$old_commit/server" "$server"
if install_server --force; then
    echo 'Symlink installation unexpectedly overwritten' >&2
    exit 1
fi
snapshot_old > "$work/after"
cmp "$work/before" "$work/after"
echo '[DONE] Offline installation regression checks passed.' 
