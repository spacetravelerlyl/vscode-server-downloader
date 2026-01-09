#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Global Variables
# =============================================================================
g_home_prefix=~
g_vscode_ser_root="${g_home_prefix}/.vscode-server"
g_target_cli_dir="${g_vscode_ser_root}"
g_target_ser_dir=""

g_tmp_dir="./tmp_vscode_server_payload"

g_release_vscode_cli_file=""
g_release_vscode_ser_file=""

g_valid_version=""
g_valid_commit_id=""

g_self_script_abs_path="$(readlink -f "$0")"
g_installer_script_file_name="vscode-server-installer.sh"
g_version_commit_map_file="$(dirname "$g_self_script_abs_path")/vscode_version_commit.sh"

MODE="install"
USER_INPUT=""
CHECK_VERSION=""
FORCE_INSTALL=0

# =============================================================================
# Logging
# =============================================================================
_log() {
    local lvl=$1 msg=$2 ts
    ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$lvl][$ts] $msg"
}
info_log(){ _log INFO "$*"; }
warn_log(){ _log WARN "$*"; }
err_log(){ _log ERR  "$*"; }

# =============================================================================
# Utilities
# =============================================================================
is_network_connected() {
    command -v nc >/dev/null 2>&1 && nc -z -w1 223.5.5.5 53 >/dev/null 2>&1
}

# ---- version key normalization ----
normalize_version_key() {
    # 1.108.0 -> 1_108_0
    echo "${1//./_}"
}

# =============================================================================
# Version → Commit Map Handling
# =============================================================================
declare -A VSCODE_VERSION_COMMIT_NORM

load_version_commit_map() {
    [ -f "$g_version_commit_map_file" ] || {
        err_log "Missing vscode_version_commit.sh"
        exit 1
    }

    # shellcheck source=/dev/null
    source "$g_version_commit_map_file"

    declare -p VSCODE_VERSION_COMMIT >/dev/null 2>&1 || {
        err_log "Invalid version commit map"
        exit 1
    }

    VSCODE_VERSION_COMMIT_NORM=()

    local ver norm
    for ver in "${!VSCODE_VERSION_COMMIT[@]}"; do
        norm="$(normalize_version_key "$ver")"
        VSCODE_VERSION_COMMIT_NORM["$norm"]="${VSCODE_VERSION_COMMIT[$ver]}"
    done
}

resolve_commit_id() {
    local input="$1"

    # empty -> latest (caller decides)
    [ -z "$input" ] && { echo ""; return; }

    # already a commit id
    if [[ "$input" =~ ^[0-9a-f]{30,40}$ ]]; then
        echo "$input"
        return
    fi

    load_version_commit_map

    local key
    key="$(normalize_version_key "$input")"

    local cid="${VSCODE_VERSION_COMMIT_NORM[$key]:-}"
    if [ -z "$cid" ]; then
        err_log "Version $input not found"
        exit 1
    fi

    echo "$cid"
}

# =============================================================================
# Install Mode (makeself runtime)
# =============================================================================
payload_path_get() {
    g_release_vscode_cli_file="$(find . -maxdepth 1 -type f -name "code-*" -print -quit)"
    g_release_vscode_ser_file="$(find . -maxdepth 1 -type f -name "vscode-server-linux-x64*" -print -quit)"

    [ -f "$g_release_vscode_cli_file" ] || {
        err_log "VS Code CLI payload not found"
        exit 1
    }

    [ -f "$g_release_vscode_ser_file" ] || {
        err_log "VS Code Server payload not found"
        exit 1
    }
}

install_env_init() {
    local commit_id="$1"
    g_target_ser_dir="${g_vscode_ser_root}/cli/servers/Stable-${commit_id}/server"
}

check_install_target() {
    local cli_target
    cli_target="$g_target_cli_dir/$(basename "$g_release_vscode_cli_file")"

    if [[ -e "$cli_target" || -d "$g_target_ser_dir" ]]; then
        if [[ "$FORCE_INSTALL" -eq 1 ]]; then
            warn_log "Existing installation detected, force overwrite enabled"
            rm -rf "$cli_target" "$g_target_ser_dir"
        else
            info_log "VS Code Server already installed, skip installation"
            info_log "Use -f or --force to overwrite"
            exit 0
        fi
    fi

    mkdir -p "$g_target_ser_dir"
}

do_install_process() {
    info_log "Installing VS Code Server"
    mv "$g_release_vscode_cli_file" "$g_target_cli_dir"
    tar -xf "$g_release_vscode_ser_file" --strip-components=1 -C "$g_target_ser_dir"
}

install_env_fini() {
    info_log "Install finished"
}

install_main() {
    info_log "Offline install mode"

    payload_path_get

    local commit_id
    commit_id="$(
        "$g_release_vscode_cli_file" --version \
        | awk '/commit/ {print $NF}' \
        | tr -d ')'
    )"

    install_env_init "$commit_id"
    check_install_target
    do_install_process
    install_env_fini
}

# =============================================================================
# Download Mode (build time)
# =============================================================================
download_env_init() {
    rm -rf "$g_tmp_dir"
    mkdir -p "$g_tmp_dir"
}

do_download() {
    local target="$1" url="$2"
    wget -q --show-progress -O "$target" "$url"
}

download_vscode_cli() {
    local commit_id="$1"

    local cli_tar="$g_tmp_dir/vscode-cli.tar.gz"
    local cli_url="https://vscode.download.prss.microsoft.com/dbazure/download/stable/${commit_id}/vscode_cli_alpine_x64_cli.tar.gz"

    do_download "$cli_tar" "$cli_url"
    tar xf "$cli_tar" -C "$g_tmp_dir"

    local cli_bin
    cli_bin="$(find "$g_tmp_dir" -name code -print -quit)"

    g_valid_version="$("$cli_bin" --version | awk 'NR==1 {for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) print $i}')"
    g_valid_commit_id="$("$cli_bin" --version | awk '/commit/ {print $NF}' | tr -d ')')"

    mv "$cli_bin" "$g_tmp_dir/code-${g_valid_commit_id}"
}

download_vscode_server() {
    local commit_id="$1"
    local server_url="https://update.code.visualstudio.com/commit:${commit_id}/server-linux-x64/stable"
    do_download "$g_tmp_dir/vscode-server-linux-x64-${commit_id}.tar.gz" "$server_url"
}

do_makeself() {
    makeself.sh --gzip "$g_tmp_dir" \
        vscode-server-offline-"$g_valid_version"-"$g_valid_commit_id".run \
        "VSCode Server Offline Installer" \
        "./$g_installer_script_file_name" -i
}

download_main() {
    info_log "Download mode"

    is_network_connected || {
        err_log "Network unavailable"
        exit 1
    }

    local commit_id
    commit_id="$(resolve_commit_id "$USER_INPUT")"
    echo "Version=$USER_INPUT CommitId=${commit_id}"

    download_env_init
    download_vscode_cli "$commit_id"
    download_vscode_server "$g_valid_commit_id"
    cp "$g_self_script_abs_path" "$g_tmp_dir/$g_installer_script_file_name"
    do_makeself
}

# =============================================================================
# Argument Parsing
# =============================================================================
usage() {
    cat <<EOF
Usage:
  $0 -d [version|commit]     Download mode
  $0 -i                      Install mode (default)
  $0 -f | --force            Force overwrite on install
  $0 --check-version <ver>
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d) MODE="download"; shift ;;
            -i) MODE="install"; shift ;;
            -f|--force)
                FORCE_INSTALL=1
                shift
                ;;
            --check-version)
                CHECK_VERSION="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                USER_INPUT="$1"
                shift
                ;;
        esac
    done
}

# =============================================================================
# Main
# =============================================================================
main() {
    parse_args "$@"

    if [ -n "$CHECK_VERSION" ]; then
        load_version_commit_map
        local key
        key="$(normalize_version_key "$CHECK_VERSION")"
        if [[ -n "${VSCODE_VERSION_COMMIT_NORM[$key]:-}" ]]; then
            echo "$CHECK_VERSION => ${VSCODE_VERSION_COMMIT_NORM[$key]}"
            exit 0
        else
            echo "$CHECK_VERSION NOT FOUND"
            exit 1
        fi
    fi

    case "$MODE" in
        install)  install_main ;;
        download) download_main ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
