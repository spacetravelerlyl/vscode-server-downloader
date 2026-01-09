#!/usr/bin/bash
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
}

resolve_commit_id() {
    local input="$1"

    # latest
    [ -z "$input" ] && { echo ""; return; }

    # commit id
    [[ "$input" =~ ^[0-9a-f]{30,40}$ ]] && { echo "$input"; return; }

    # version
    load_version_commit_map
    local cid="${VSCODE_VERSION_COMMIT[$input]:-}"
    [ -n "$cid" ] || {
        err_log "Version $input not found in version map"
        exit 1
    }
    info_log "Resolved version $input → commit $cid"
    echo "$cid"
}

# =============================================================================
# Install Mode (makeself runtime)
# =============================================================================
payload_path_get() {
    g_release_vscode_cli_file="$(find . -maxdepth 1 -type f -name "code-*" -print -quit)"
    g_release_vscode_ser_file="$(find . -maxdepth 1 -type f -name "vscode-server-linux-x64*" -print -quit)"
}

install_env_init() {
    local commit_id="$1"
    g_target_ser_dir="${g_vscode_ser_root}/cli/servers/Stable-${commit_id}/server"

    if [ ! -d "$g_target_ser_dir" ]; then
        mkdir -p "$g_target_ser_dir"
    else
        warn_log "Server directory already exists, skipping creation"
    fi
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

    g_valid_version="$("$cli_bin" --version | awk 'NR==1')"
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
  $0 --check-version <ver>
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d) MODE="download"; shift ;;
            -i) MODE="install"; shift ;;
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
        if [[ -n "${VSCODE_VERSION_COMMIT[$CHECK_VERSION]:-}" ]]; then
            echo "$CHECK_VERSION => ${VSCODE_VERSION_COMMIT[$CHECK_VERSION]}"
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
