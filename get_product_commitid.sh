#!/usr/bin/env bash
set -euo pipefail

# ========= Configuration =========
DIR="./vscode-linux-x64-stable"
OUT_SH="vscode_version_commit.sh"
MIN_VERSION="1.81.1"
PRODUCT_JSON_PATH="VSCode-linux-x64/resources/app/product.json"

GITHUB_OWNER="${GITHUB_OWNER:-microsoft}"
GITHUB_REPO="${GITHUB_REPO:-vscode}"
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"
GITHUB_GRAPHQL_URL="${GITHUB_GRAPHQL_URL:-https://api.github.com/graphql}"
REPO_URL="${REPO_URL:-https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git}"
# ================================

MODE="graphql"
FORCE=0
WRITE_SH=1
PRINT_STDOUT=1

declare -A VSCODE_VERSION_COMMIT=()
declare -A FETCHED_VERSION_COMMIT=()

info() { echo "[INFO] $*" >&2; }
warn() { echo "[WARN] $*" >&2; }
err() { echo "[ERR] $*" >&2; }

usage() {
    cat <<EOF
Usage:
  $0 [mode] [options]

Modes:
  graphql             Use GitHub GraphQL API (default)
  api                 Use GitHub REST API
  git                 Use git ls-remote
  local               Extract commits from downloaded VS Code tar files

Options:
  -f, --force         Rebuild output without merging existing ${OUT_SH}
  --min-version <ver> Minimum version to output (default: ${MIN_VERSION})
  --out-sh <file>     Bash map output file (default: ${OUT_SH})
  --no-write-sh       Do not write Bash map output file
  --no-stdout         Do not print "version commit_sha" lines
  -h, --help          Show this help

Environment:
  GITHUB_TOKEN        GitHub token. Required for graphql mode; optional for api mode.
  GITHUB_OWNER        GitHub owner (default: ${GITHUB_OWNER})
  GITHUB_REPO         GitHub repo (default: ${GITHUB_REPO})
  REPO_URL            Git URL for git mode (default: ${REPO_URL})
EOF
}

require_value() {
    local opt="$1" val="${2:-}"
    if [[ -z "$val" || "$val" == -* ]]; then
        err "$opt requires a value"
        usage >&2
        exit 1
    fi
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        err "Missing dependency: $cmd"
        exit 1
    fi
}

require_github_token_for_graphql() {
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        err "graphql mode requires GITHUB_TOKEN because GitHub GraphQL API does not allow anonymous requests"
        err "Use '$0 api' or '$0 git' if you need to run without a token"
        exit 1
    fi
}

version_ge() {
    local IFS=.
    # shellcheck disable=SC2206
    local v1=($1)
    # shellcheck disable=SC2206
    local v2=($2)
    local i
    for ((i=0; i<3; i++)); do
        ((10#${v1[i]} > 10#${v2[i]})) && return 0
        ((10#${v1[i]} < 10#${v2[i]})) && return 1
    done
    return 0
}

is_semver_tag() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

add_mapping() {
    local version="$1" commit="$2"

    is_semver_tag "$version" || return 0
    version_ge "$version" "$MIN_VERSION" || return 0

    if [[ ! "$commit" =~ ^[0-9a-f]{40}$ ]]; then
        warn "Skip invalid commit for $version: $commit"
        return 0
    fi

    VSCODE_VERSION_COMMIT["$version"]="$commit"
    FETCHED_VERSION_COMMIT["$version"]="$commit"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            graphql|api|git|local)
                MODE="$1"
                shift
                ;;
            -f|--force)
                FORCE=1
                shift
                ;;
            --min-version)
                require_value "$1" "${2:-}"
                MIN_VERSION="$2"
                shift 2
                ;;
            --out-sh)
                require_value "$1" "${2:-}"
                OUT_SH="$2"
                WRITE_SH=1
                shift 2
                ;;
            --no-write-sh)
                WRITE_SH=0
                shift
                ;;
            --no-stdout)
                PRINT_STDOUT=0
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                err "Unknown argument: $1"
                usage >&2
                exit 1
                ;;
        esac
    done
}

load_existing_map() {
    if [[ -f "$OUT_SH" && "$FORCE" -eq 0 ]]; then
        # shellcheck source=/dev/null
        source "$OUT_SH"
    fi

    if [[ "$FORCE" -eq 1 ]]; then
        VSCODE_VERSION_COMMIT=()
    fi
}

github_get() {
    local url="$1" body_file headers_file status message
    body_file="$(mktemp)"
    headers_file="$(mktemp)"

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        status="$(
            curl -sS -L \
                -H "Accept: application/vnd.github+json" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                -H "Authorization: Bearer ${GITHUB_TOKEN}" \
                -D "$headers_file" \
                -o "$body_file" \
                -w "%{http_code}" \
                "$url"
        )" || {
            rm -f "$body_file" "$headers_file"
            err "Network request failed: $url"
            exit 1
        }
    else
        status="$(
            curl -sS -L \
                -H "Accept: application/vnd.github+json" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                -D "$headers_file" \
                -o "$body_file" \
                -w "%{http_code}" \
                "$url"
        )" || {
            rm -f "$body_file" "$headers_file"
            err "Network request failed: $url"
            exit 1
        }
    fi

    if [[ ! "$status" =~ ^2 ]]; then
        message="$(jq -r '.message // empty' "$body_file" 2>/dev/null || true)"
        rm -f "$body_file" "$headers_file"
        err "GitHub API request failed with HTTP $status: ${message:-$url}"
        exit 1
    fi

    cat "$body_file"
    rm -f "$body_file" "$headers_file"
}

github_graphql() {
    local query="$1" variables="$2" payload body_file status message
    body_file="$(mktemp)"
    payload="$(jq -cn --arg query "$query" --argjson variables "$variables" '{query:$query, variables:$variables}')"

    status="$(
        curl -sS -L \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            -H "Content-Type: application/json" \
            -o "$body_file" \
            -w "%{http_code}" \
            -d "$payload" \
            "$GITHUB_GRAPHQL_URL"
    )" || {
        rm -f "$body_file"
        err "Network request failed: $GITHUB_GRAPHQL_URL"
        exit 1
    }

    if [[ ! "$status" =~ ^2 ]]; then
        message="$(jq -r '.message // empty' "$body_file" 2>/dev/null || true)"
        rm -f "$body_file"
        err "GitHub GraphQL request failed with HTTP $status: ${message:-request failed}"
        exit 1
    fi

    if jq -e '.errors and (.errors | length > 0)' "$body_file" >/dev/null; then
        message="$(jq -r '[.errors[]?.message] | join(";")' "$body_file")"
        rm -f "$body_file"
        err "GitHub GraphQL returned errors: $message"
        exit 1
    fi

    cat "$body_file"
    rm -f "$body_file"
}

fetch_graphql() {
    require_cmd curl
    require_cmd jq
    require_github_token_for_graphql

    local cursor="null" has_next="true" response query variables
    query='
query($owner: String!, $repo: String!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    refs(refPrefix: "refs/tags/", first: 100, after: $cursor, orderBy: {field: TAG_COMMIT_DATE, direction: DESC}) {
      nodes {
        name
        target {
          __typename
          oid
          ... on Tag {
            target {
              __typename
              oid
              ... on Commit {
                oid
              }
            }
          }
          ... on Commit {
            oid
          }
        }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}'

    info "Fetching tags with GitHub GraphQL API"
    while [[ "$has_next" == "true" ]]; do
        variables="$(jq -cn \
            --arg owner "$GITHUB_OWNER" \
            --arg repo "$GITHUB_REPO" \
            --argjson cursor "$cursor" \
            '{owner:$owner, repo:$repo, cursor:$cursor}')"
        response="$(github_graphql "$query" "$variables")"

        while read -r version commit; do
            add_mapping "$version" "$commit"
        done < <(
            jq -r '
          .data.repository.refs.nodes[]
          | .name as $name
          | (
              if .target.__typename == "Commit" then .target.oid
              elif .target.__typename == "Tag" and .target.target.__typename == "Commit" then .target.target.oid
              else empty
              end
            ) as $commit
          | select($commit != null and $commit != "")
          | "\($name) \($commit)"
            ' <<< "$response"
        )

        has_next="$(jq -r '.data.repository.refs.pageInfo.hasNextPage' <<< "$response")"
        cursor="$(jq -c '.data.repository.refs.pageInfo.endCursor' <<< "$response")"
    done
}

resolve_rest_tag_commit() {
    local tag="$1" ref_json type sha tag_json
    ref_json="$(github_get "${GITHUB_API_URL}/repos/${GITHUB_OWNER}/${GITHUB_REPO}/git/ref/tags/${tag}")"
    type="$(jq -r '.object.type // empty' <<< "$ref_json")"
    sha="$(jq -r '.object.sha // empty' <<< "$ref_json")"

    case "$type" in
        commit)
            echo "$sha"
            ;;
        tag)
            tag_json="$(github_get "${GITHUB_API_URL}/repos/${GITHUB_OWNER}/${GITHUB_REPO}/git/tags/${sha}")"
            jq -r 'if .object.type == "commit" then .object.sha else empty end' <<< "$tag_json"
            ;;
        *)
            warn "Unknown ref object type for tag $tag: ${type:-empty}"
            ;;
    esac
}

fetch_api() {
    require_cmd curl
    require_cmd jq

    local page=1 tags_json count version commit

    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        warn "GITHUB_TOKEN is not set; REST API mode may hit GitHub rate limits"
    fi

    info "Fetching tags with GitHub REST API"
    while true; do
        tags_json="$(github_get "${GITHUB_API_URL}/repos/${GITHUB_OWNER}/${GITHUB_REPO}/tags?per_page=100&page=${page}")"
        count="$(jq 'length' <<< "$tags_json")"
        [[ "$count" -gt 0 ]] || break

        while read -r version; do
            is_semver_tag "$version" || continue
            version_ge "$version" "$MIN_VERSION" || continue
            commit="$(resolve_rest_tag_commit "$version")"
            [[ -n "$commit" ]] || {
                warn "Could not resolve commit for tag $version"
                continue
            }
            add_mapping "$version" "$commit"
        done < <(jq -r '.[].name' <<< "$tags_json")

        page=$((page + 1))
    done
}

fetch_git() {
    require_cmd git

    local version commit ref peeled ls_remote_output
    declare -A direct_refs=()
    declare -A peeled_refs=()

    info "Fetching tags with git ls-remote"
    if ! ls_remote_output="$(git ls-remote --tags "$REPO_URL")"; then
        err "git ls-remote failed: $REPO_URL"
        exit 1
    fi

    while read -r commit ref; do
        [[ "$ref" == refs/tags/* ]] || continue

        if [[ "$ref" == *'^{}' ]]; then
            peeled="${ref#refs/tags/}"
            peeled="${peeled%\^\{\}}"
            peeled_refs["$peeled"]="$commit"
        else
            version="${ref#refs/tags/}"
            direct_refs["$version"]="$commit"
        fi
    done <<< "$ls_remote_output"

    for version in "${!direct_refs[@]}"; do
        commit="${peeled_refs[$version]:-${direct_refs[$version]}}"
        add_mapping "$version" "$commit"
    done
}

fetch_local() {
    require_cmd jq

    local file version json commit

    info "Extracting commits from local tar files in $DIR"
    for file in "${DIR}"/vscode-*-linux-x64.tar.gz; do
        [[ -f "$file" ]] || continue

        version="$(basename "$file" | sed -E 's/^vscode-([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/')"
        is_semver_tag "$version" || continue
        version_ge "$version" "$MIN_VERSION" || continue

        if [[ "$FORCE" -eq 0 && -n "${VSCODE_VERSION_COMMIT[$version]:-}" ]]; then
            continue
        fi

        if ! json="$(tar -xOzf "$file" "$PRODUCT_JSON_PATH" 2>/dev/null)"; then
            warn "Missing product.json: $version"
            continue
        fi

        commit="$(jq -r '.commit // empty' <<< "$json")"
        [[ -n "$commit" && "$commit" != "null" ]] || continue
        add_mapping "$version" "$commit"
    done
}

write_bash_map() {
    {
        echo "#!/usr/bin/env bash"
        echo "# Auto-generated by $(basename "$0") at $(date)"
        echo "# DO NOT EDIT MANUALLY"
        echo
        echo "declare -A VSCODE_VERSION_COMMIT=("

        for v in "${!VSCODE_VERSION_COMMIT[@]}"; do
            printf '  ["%s"]="%s"\n' "$v" "${VSCODE_VERSION_COMMIT[$v]}"
        done | sort -V

        echo ")"
    } > "$OUT_SH"

    chmod +x "$OUT_SH"
    info "Hash table written to $OUT_SH"
}

print_mappings() {
    for v in "${!FETCHED_VERSION_COMMIT[@]}"; do
        printf '%s %s\n' "$v" "${FETCHED_VERSION_COMMIT[$v]}"
    done | sort -Vr
}

main() {
    parse_args "$@"
    load_existing_map

    info "Mode        : $MODE"
    info "Min version : $MIN_VERSION"
    info "Force       : $FORCE"

    case "$MODE" in
        graphql) fetch_graphql ;;
        api) fetch_api ;;
        git) fetch_git ;;
        local) fetch_local ;;
        *)
            err "Unsupported mode: $MODE"
            usage >&2
            exit 1
            ;;
    esac

    if [[ "$WRITE_SH" -eq 1 ]]; then
        write_bash_map
    fi

    if [[ "$PRINT_STDOUT" -eq 1 ]]; then
        print_mappings
    fi
}

main "$@"
