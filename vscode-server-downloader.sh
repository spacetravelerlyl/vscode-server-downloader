#!/usr/bin/bash

g_home_prefix=~
g_vscode_ser_root="${g_home_prefix}/.vscode-server"
g_target_cli_dir=${g_vscode_ser_root}
g_target_ser_dir=""
g_release_vscode_cli_file=""
g_release_vscode_ser_file=""

g_valid_version=""
g_valid_commit_id=""
g_tmp_dir="./tmp_vscode_server_payload"
g_cli_file_path=""
g_ser_file_path=""
g_self_script_abs_path="$(readlink -f "$0")"
g_installer_script_file_name="vscode-server-installer.sh"

# tar -xOf vscode-1.99.3-linux-x64.tar.gz VSCode-linux-x64/resources/app/product.json | jq -r '.commit'

_log()
{
    local log_level=$1
    local log_content=$2
    local timestamp
    local log_prefix
    local color_reset
    local color

    color_reset="\033[0m"
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    case "$log_level" in
        INFO)
            log_prefix="[INFO] [$timestamp]"
            color="\033[32m"  # green
            ;;
        WARN)
            log_prefix="[WARN] [$timestamp]"
            color="\033[33m"  # yellow
            ;;
        ERR)
            log_prefix="[ERR ] [$timestamp]"
            color="\033[31m"  # red
            ;;
        *)
            echo -e "\033[31m[ERR ] [$timestamp] 不支持的日志级别: $log_level\033[0m"
            return 1
            ;;
    esac

    if [ -t 1 ]; then
        echo -e "${color}${log_prefix} ${log_content}${color_reset}"
    else
        echo "${log_prefix} ${log_content}"
    fi
}

info_log() 
{
    if [ $# -eq 0 ]; then
        return 1
    fi
    _log "INFO" "$*"
}

warn_log() 
{
    if [ $# -eq 0 ]; then
        return 1
    fi
    _log "WARN" "$*"
}

err_log() 
{
    if [ $# -eq 0 ]; then
        return 1
    fi
    _log "ERR" "$*"
}

install_env_init()
{
    info_log "Install env init."
    commit_id=$1
    g_target_ser_dir="${g_vscode_ser_root}/cli/servers/Stable-${commit_id}/server"

    if [ -d "$g_target_ser_dir" ]; then
        info_log "Create $g_target_ser_dir"

        # Create server installation directory
        mkdir -p "${g_target_ser_dir}"
    else
        warn_log "The $g_target_ser_dir directory already exists, skipping the installation process."
        # exit 0
    fi
}

payload_path_get()
{
    info_log "Payload path get."
    # The extracted files (e.g., /tmp/selfgz106447/code-0f0d87fa9e96c856c5212fc86db137ac0d783365)
    g_release_vscode_cli_file="$(find . -maxdepth 1 -type f -name "code-*" -print0 | xargs -0 | xargs -I {} readlink -f {})"

    # The extracted files (e.g., /tmp/selfgz106447/vscode-server-linux-x64-0f0d87fa9e96c856c5212fc86db137ac0d783365.tar.gz)
    g_release_vscode_ser_file="$(find . -maxdepth 1 -type f -name "vscode-server-linux-x64*" -print0 | xargs -0 | xargs -I {} readlink -f {})"

    info_log "Extracted cli files:$g_release_vscode_cli_file"
    info_log "Extracted server files:$g_release_vscode_ser_file"
}

do_install_process()
{
    info_log "Do install process."
    # Install code cli and extract vscode-server

    # mv "${g_release_vscode_cli_file}" ${g_target_cli_dir}
    # tar -xf "${g_release_vscode_ser_file}" --strip-components=1 -C "$g_target_ser_dir"
}

install_env_fini()
{
    # Delete the temporary release directory, Makeself auto-completes
    info_log "Install finished."
}

download_env_init()
{
    rm -frv ${g_tmp_dir}/*
    mkdir -p ${g_tmp_dir}
}

# $1 target file name 
# $2 url
do_download_process()
{
    local target="$1"
    local url="$2"
    WGET_COMMON_OPTS=(
        '--user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"'
        '--max-redirect=10'
        '--no-check-certificate'
        '--quiet' 
        '--show-progress' 
        '--progress=bar:force'
    )

    if wget "${WGET_COMMON_OPTS[@]}" -O "${target}" "${url}"; then
        if [ -s "${target}" ]; then
            info_log "Download ${target} success, size: $(du -h "${target}" | awk '{print $1}')"
        else
            err_log "Download ${target} failed, empty file."
            exit 1
        fi
    else
        err_log "Download ${target} failed: wget execution returns a non-zero exit code: wget_exit_code=$?"
        exit 1
    fi
}

download_vscode_cli()
{
    local tmp_payload_dir=$1
    local commit_id=$2
    local id_length
    local finial_vscode_cli_url

    local TARGET_CLI_FILE_NAME
    local RAW_CODE_FILE_NAME
    local BASE_VSCODE_CLI_URL

    TARGET_CLI_FILE_NAME="${tmp_payload_dir}/vscode-cli-alpine-x64.tar.gz"
    RAW_CODE_FILE_NAME="${tmp_payload_dir}/code"
    BASE_VSCODE_CLI_URL='https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64'

    id_length=${#commit_id}
    finial_vscode_cli_url="${BASE_VSCODE_CLI_URL}"
    if [ "$id_length" -eq 0 ]; then
        finial_vscode_cli_url+='&platform=linux-x64'
    elif [ "$id_length" -lt 30 ]; then
        info_log "The length of the commit_id=\"${commit_id}\" is less than 30, treat it as a version number."
        err_log "Don't support download by verion."
        exit 1
    else
        finial_vscode_cli_url="https://vscode.download.prss.microsoft.com/dbazure/download/stable/${commit_id}/vscode_cli_alpine_x64_cli.tar.gz"
    fi

    info_log "Request: ${finial_vscode_cli_url}"
    do_download_process "${TARGET_CLI_FILE_NAME}" "${finial_vscode_cli_url}"

    tar xf "${TARGET_CLI_FILE_NAME}" -C "${tmp_payload_dir}"
    rm -fv "${TARGET_CLI_FILE_NAME}"

    g_valid_version=$(./"$RAW_CODE_FILE_NAME" --version | awk '{print $2}')
    g_valid_commit_id=$(./"$RAW_CODE_FILE_NAME" --version | awk '/commit/ {print $NF}' | tr -d ')')

    if [ -n "$commit_id" ]; then
        if [ "$g_valid_commit_id" != "$commit_id" ]; then
            err_log "the downloaded commit id is $g_valid_commit_id, but expect commit is $commit_id"
            exit 1
        else
            info_log "the downloaded commit id is $g_valid_commit_id, expect commit is $commit_id, success"
        fi
    fi

    g_cli_file_path="$RAW_CODE_FILE_NAME-${g_valid_commit_id}"
    mv "$RAW_CODE_FILE_NAME" "${g_cli_file_path}"
}

download_vscode_server()
{
    tmp_payload_dir=$1
    commit_id=$2
    g_ser_file_path="${tmp_payload_dir}/vscode-server-linux-x64-${commit_id}.tar.gz"
    vscode_server_url="https://update.code.visualstudio.com/commit:${commit_id}/server-linux-x64/stable"
    do_download_process "${g_ser_file_path}" "${vscode_server_url}"
}

copy_self_to_tmp_dir()
{
    tmp_payload_dir="$1"
    cp -frv "$g_self_script_abs_path" "${tmp_payload_dir}/${g_installer_script_file_name}"
}

do_makeself()
{
    tmp_payload_dir="$1"
    version_str="$2"
    commit_id="$3"
    makeself.sh --gzip "${tmp_payload_dir}" vscode-server-installer-offline-allinone-"${version_str}"-"${commit_id}".run \
    "VSCode Server Offline All In One Installer" ./"${g_installer_script_file_name}" -i
}

usage() 
{
    cat <<EOF
Usage:
  $0 -d        Download mode
  $0 -i        Install mode (default)
  $0           Install mode (default)
EOF
}

is_network_connected()
{
    # ali DNS testing
    command -v nc >/dev/null 2>&1 && nc -z -w1 223.5.5.5 53 >/dev/null 2>&1
}

# ----------------------------
# Parameter Parsing
# ----------------------------
MODE="install"
while getopts ":di" opt; do
    case "$opt" in
        d) MODE="download" ;;
        i) MODE="install" ;;
        *)
            usage
            exit 1
            ;;
    esac
done

shift $((OPTIND - 1))

if [ "$MODE" = "install" ]; then
    info_log "Offline install mode"
    payload_path_get
    install_env_init "$("$g_release_vscode_cli_file" --version | awk '/commit/ {print $NF}' | tr -d ')')"
    do_install_process
    install_env_fini
else
    info_log "Download mode"

    if is_network_connected; then
        info_log "✅ The system is connected to the Internet."
    else
        err_log "❌ The system is not connected to the Internet."
        exit 1
    fi    

    expcet_commit_id="$1"

    download_env_init
    download_vscode_cli $g_tmp_dir "$expcet_commit_id"
    download_vscode_server $g_tmp_dir "$g_valid_commit_id"
    copy_self_to_tmp_dir "$g_tmp_dir"
    do_makeself "$g_tmp_dir" "$g_valid_version" "$g_valid_commit_id"
fi