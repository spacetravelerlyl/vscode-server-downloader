# VS Code Server 离线下载与安装

本项目用于获取 VS Code 版本与 commit 的映射，下载对应的 CLI 和 Server，并生成可在离线 Linux x64 环境运行的 `.run` 安装包。目前脚本固定使用 Stable 通道，不提供 ARM、Windows 或 macOS 安装包。

请在仓库根目录执行下文命令。多数输入、缓存和输出路径相对于当前工作目录；打包脚本读取的映射文件则位于脚本自身所在目录。

## 脚本一览

| 脚本 | 功能 | 输入 | 输出或修改范围 |
| --- | --- | --- | --- |
| `download_all_release.sh` | 批量下载 VS Code 桌面版 Linux x64 压缩包，供本地提取 commit | 微软 Stable 版本列表、可选的已有映射 | `vscode-linux-x64-stable/`，不更新映射，不生成 Server 安装包 |
| `get_product_commitid.sh` | 从 GitHub 标签或本地桌面版压缩包获取版本与 commit 映射 | GraphQL、REST、Git 或本地 tar 包 | 默认合并并写入 `vscode_version_commit.sh`，同时向标准输出打印本次获取的映射 |
| `vscode_version_commit.sh` | 保存 `VSCODE_VERSION_COMMIT` Bash 关联数组 | 由映射生成脚本维护 | 供其他脚本 `source`，直接执行不会下载或安装 |
| `vscode-server-downloader.sh` | 下载 CLI、Server 并打包；也作为安装包内部的安装脚本 | 指定版本或完整 commit；安装时读取随包携带的文件 | 下载缓存、临时载荷、`.run` 文件；安装时写入指定 Server 根目录 |
| `check.sh` | 运行本地检查和离线安装回归检查 | 仓库脚本和映射 | 检查日志、退出状态，不联网、不打包 |
| `tests/offline-install.sh` | 单独验证安装逻辑及旧版本保留行为 | 自动构造的模拟 CLI、Server 载荷 | 仅在临时目录安装，退出时自动清理 |

`tmp_vscode_server_payload/vscode-server-installer.sh` 是打包时复制的安装脚本，不是独立维护的源文件；修改安装逻辑后需要重新打包。

## 环境依赖

| 场景 | 依赖 |
| --- | --- |
| 通用 | Linux、Bash 4+（使用关联数组）、常用 GNU 工具，如 `tar`、`gzip`、`awk`、`sed`、`find`、coreutils |
| 批量下载桌面版 | `curl` 或 `wget`，以及 `jq` |
| GraphQL / REST 获取映射 | `curl`、`jq`；GraphQL 必须提供 `GITHUB_TOKEN` |
| Git 获取映射 | `git`，无需完整克隆仓库 |
| 从本地压缩包提取映射 | `tar`、`jq` |
| 生成离线安装包 | `makeself.sh` 在 `PATH` 中；缓存不完整时还需 `curl` 或 `wget`；打包过程会运行下载的 x64 CLI |
| 运行离线安装包 | Bash、`tar`、`gzip` 和常用 GNU 工具；不需要网络、`jq`、Git 或 makeself |
| 本地检查 | 额外使用 `sha256sum`、`cmp`；`shellcheck` 可选，缺失时打印跳过提示 |

下载脚本优先使用 curl，其调用包含 `--retry-all-errors`，需使用支持该选项的版本；wget 路径建议使用 1.16+。目标系统还需满足所选 VS Code Server 版本自身的运行要求。

可通过系统软件包安装 makeself，安装后确认命令可用：

```bash
sudo apt install makeself
command -v makeself.sh
```

也可从 [makeself 项目](https://github.com/megastep/makeself) 下载发行包，解包后将其目录加入 `PATH`，例如：

```bash
export PATH="$PATH:/opt/makeself"
```

## 常用流程：更新映射、打包、离线安装

1. 在联网环境更新版本映射，默认保留旧条目：

   ```bash
   bash get_product_commitid.sh git
   ```

2. 选择与本地 VS Code「帮助 → 关于」中版本和 commit 对应的 Server，检查并打包。例如：

   ```bash
   bash vscode-server-downloader.sh --check-version 1.145.2
   bash vscode-server-downloader.sh -d 1.145.2
   ```

3. 将生成的 `.run` 文件复制到离线主机，使用运行 Remote-SSH 的目标用户执行：

   ```bash
   ./vscode-server-offline-1.145.2-c4453f8ea430795f941c1b2ff6c9321135a74a02.run
   ```

4. 从对应版本的本地 VS Code 通过 Remote-SSH 连接。安装包只准备文件，不启动 Server 或建立 SSH 连接。

上面的版本仅为命令示例。`-d` 必须显式指定版本或 commit，不会自动查询最新版本。若已有准确的完整 commit，可以跳过映射更新：

```bash
bash vscode-server-downloader.sh -d c4453f8ea430795f941c1b2ff6c9321135a74a02
```

## download_all_release.sh：批量下载桌面版

从微软更新服务获取 Stable 版本列表，默认处理 `1.81.1` 及以上版本，将桌面版压缩包保存为：

```text
vscode-linux-x64-stable/vscode-<version>-linux-x64.tar.gz
```

此步骤仅在需要桌面版归档或准备使用 `get_product_commitid.sh local` 时执行。直接通过 GitHub 获取映射、打包 Server 不需要先批量下载桌面版。

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-f` / `--force` | 关闭 | 忽略已有映射和已下载文件的跳过规则，重新下载 |
| `--min-version <ver>` | `1.81.1` | 包含此版本在内的最低版本 |
| `--parallel <n>` | `1` | 并发任务数，必须大于 0；按批次等待任务结束 |
| `--sleep-min <sec>` | `0` | 每个成功下载任务结束后的最小等待秒数，非负整数 |
| `--sleep-max <sec>` | `0` | 最大等待秒数，必须不小于最小值；范围内随机等待 |
| `-h` / `--help` | — | 显示帮助 |

```bash
bash download_all_release.sh
bash download_all_release.sh --min-version 1.140.0 --parallel 4
bash download_all_release.sh --sleep-min 10 --sleep-max 30
bash download_all_release.sh --force
```

默认先读取当前目录的 `vscode_version_commit.sh`：有映射的版本直接跳过，即使本地没有桌面版 tar 包；无映射但 tar 包已存在时也跳过。若要补齐归档文件，可使用 `--force`。下载失败保留 `.tmp` 文件供下次续传，存在失败任务时最终返回非零状态。脚本本身不会从压缩包提取 commit 或更新映射。

## get_product_commitid.sh：生成版本映射

```bash
bash get_product_commitid.sh [mode] [options]
```

| 模式 | 数据来源 | 依赖与特点 |
| --- | --- | --- |
| `graphql`（默认） | GitHub GraphQL 标签查询 | 需要 `curl`、`jq`、`GITHUB_TOKEN`，自动分页 |
| `api` | GitHub REST 标签查询 | 需要 `curl`、`jq`；Token 可选，匿名访问可能受限流影响 |
| `git` | `git ls-remote --tags` | 需要 Git；无需 Token 或完整克隆，支持解析附注标签指向的 commit |
| `local` | 当前目录下的 `vscode-linux-x64-stable/*.tar.gz` | 从 `VSCode-linux-x64/resources/app/product.json` 提取 commit，不联网 |

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-f` / `--force` | 关闭 | 不合并已有映射，从本次数据重建输出；不会强制下载桌面版 |
| `--min-version <ver>` | `1.81.1` | 本次获取条目的最低版本；默认合并时不删除已有低版本条目 |
| `--out-sh <file>` | `vscode_version_commit.sh` | 指定读入合并及写出的映射文件；此选项也会启用写文件 |
| `--no-write-sh` | 默认写文件 | 只获取结果，不写映射文件 |
| `--no-stdout` | 默认打印 | 不打印本次获取的 `version commit_sha` 行；日志仍写到标准错误 |
| `-h` / `--help` | — | 显示帮助 |

```bash
# 默认 GraphQL 模式，使用环境中已配置的 Token
GITHUB_TOKEN="$GITHUB_TOKEN" bash get_product_commitid.sh

# 无 Token 时可选择 Git 或 REST 模式
bash get_product_commitid.sh git
bash get_product_commitid.sh api

# 从本地桌面版包增量提取
bash get_product_commitid.sh local

# 只打印本次获取的映射，不修改文件
bash get_product_commitid.sh git --no-write-sh

# 另存映射，不打印结果行
bash get_product_commitid.sh git --out-sh /tmp/vscode-map.sh --no-stdout

# 从本次获取的数据重建映射，而非合并旧文件
bash get_product_commitid.sh git --force --min-version 1.140.0
```

默认会读入旧映射，合并本次结果，再按版本升序写回 Bash 文件；本次结果可以更新同版本的旧 commit。`local` 模式默认跳过已有映射的版本。标准输出仅包含本次获取的映射，按版本降序排列；不会把所有保留的旧条目再次打印。

可用环境变量：

| 变量 | 默认值 / 说明 |
| --- | --- |
| `GITHUB_TOKEN` | GraphQL 必填，REST 可选 |
| `GITHUB_OWNER` | `microsoft` |
| `GITHUB_REPO` | `vscode` |
| `GITHUB_API_URL` | `https://api.github.com` |
| `GITHUB_GRAPHQL_URL` | `https://api.github.com/graphql` |
| `REPO_URL` | `https://github.com/<owner>/<repo>.git`，用于 Git 模式 |

## vscode_version_commit.sh：映射数据

此文件定义 Bash 关联数组，没有命令行参数，也不会自动联网更新。可在 Bash 中读取：

```bash
source ./vscode_version_commit.sh
printf '%s\n' "${VSCODE_VERSION_COMMIT[1.145.2]}"
```

通常通过 `get_product_commitid.sh` 更新。按版本打包时，`vscode-server-downloader.sh` 会读取与它同目录的此文件；按完整 commit 打包不依赖此文件。离线安装包也不需要额外携带映射文件。

## vscode-server-downloader.sh：下载、打包与安装

### 下载打包模式

```bash
bash vscode-server-downloader.sh -d <version|commit> [--force-download]
```

| 参数 | 说明 |
| --- | --- |
| `-d <version\|commit>` | 下载并打包指定版本；commit 请提供完整的 40 位小写十六进制值 |
| `--force-download` | 忽略已有完整缓存，重新发起 CLI 和 Server 下载；保留的部分 `.tmp` 文件仍可能用于续传 |
| `--check-version <ver>` | 查询本地映射并退出；未找到返回非零状态，不联网 |
| `-h` / `--help` | 显示帮助 |

CLI 使用 `commit:<commit>/cli-alpine-x64/stable` 官方下载入口，Server 使用 `commit:<commit>/server-linux-x64/stable`。打包时会运行 CLI 核对版本和 commit，确认与请求一致。

```bash
bash vscode-server-downloader.sh -d 1.145.2
bash vscode-server-downloader.sh -d 1.145.2 --force-download
bash vscode-server-downloader.sh --check-version 1.145.2
```

输出与中间文件：

| 路径 | 内容 |
| --- | --- |
| `.cache/vscode-server-downloader/vscode-cli/<commit>.tar.gz` | CLI 下载缓存 |
| `.cache/vscode-server-downloader/vscode-server/vscode-server-linux-x64-<commit>.tar.gz` | Server 下载缓存 |
| `tmp_vscode_server_payload/` | 打包载荷，每次打包会删除并重建；不要用于存放其他文件 |
| `vscode-server-offline-<version>-<commit>.run` | 最终自解压安装包；同名重新打包会覆盖 |

缓存齐全时可直接复用，不需要联网。不要同时启动多个打包任务，它们共享临时载荷目录。`--force` 是安装选项，不能替代下载时的 `--force-download`。

### 离线安装模式

日常安装直接执行生成的 `.run`。传给内部安装脚本的参数放在 makeself 的 `--` 之后：

```bash
# 默认安装到当前用户的 ~/.vscode-server
./vscode-server-offline-<version>-<commit>.run

# 指定安装根目录
./vscode-server-offline-<version>-<commit>.run -- --install-dir /data/vscode-server

# 显式重装当前 commit
./vscode-server-offline-<version>-<commit>.run -- --force

# 只验证自解压包完整性，不安装
./vscode-server-offline-<version>-<commit>.run --check
```

| 内部安装参数 / 环境变量 | 说明 |
| --- | --- |
| `-i` | 安装模式，也是脚本默认模式；`.run` 已自动传入 |
| `--install-dir <path>` | 安装根目录，优先于环境变量；应与 Remote-SSH 的 `remote.SSH.serverInstallPath` 配置一致 |
| `VSCODE_AGENT_FOLDER` | 未传 `--install-dir` 时使用的安装根目录；默认 `~/.vscode-server` |
| `-f` / `--force` | 允许替换当前包对应 commit 的 CLI、Server |

若要直接调用源码安装，必须先切换到含有 `code-<commit>` 和 `vscode-server-linux-x64-<commit>.tar.gz` 的载荷目录，再执行脚本绝对路径：

```bash
# 在仓库根目录开始
installer_script="$PWD/vscode-server-downloader.sh"
cd tmp_vscode_server_payload
bash "$installer_script" -i --install-dir /tmp/vscode-server-test
```

默认安装布局：

```text
~/.vscode-server/
├── code-<commit>
├── cli/servers/Stable-<commit>/server/
└── bin/<commit> -> 对应的 server 目录（仅原路径不存在时创建）
```

安装时的已有环境保护规则：

- 不同 commit 分目录共存，安装器不清理其他版本，不修改扩展、设置、缓存索引，也不停止运行中的进程。
- 同 commit 的 CLI、Server 关键可执行文件完整时，默认跳过安装。
- 仅有 CLI、没有 Server 时，默认保留 CLI 并安装 Server。
- Server 路径已存在但安装不完整时，默认报错并保留原状；只有显式传入 `--force` 才替换当前 commit。
- 当前 commit 的 CLI、`Stable-<commit>` 或 `server` 路径若为符号链接，即使 `--force` 也拒绝覆盖。
- 已有 `bin/<commit>` 目录或链接保持原样；不存在时才创建兼容旧版 Remote-SSH 的链接。
- 先在临时目录解包并检查 Server 的 `bin/code-server` 和 `node`，解包或检查失败不会替换原 Server。安装器根据载荷文件名核对 CLI、Server 的 commit，不运行 CLI。

应使用目标用户执行安装，避免使用 sudo 后装进 root 的用户目录。上述规则约束安装器的文件操作，Server 启动后的行为由 VS Code 自身控制。

目录结构参考：[微软 CLI 源码](https://github.com/microsoft/vscode/blob/main/cli/src/tunnels/paths.rs)。

### 可选：生成和验证 SHA-256 文件

打包脚本不会自动生成 `.sha256` 文件，需要时执行：

```bash
sha256sum vscode-server-offline-<version>-<commit>.run > vscode-server-offline-<version>-<commit>.run.sha256
sha256sum -c vscode-server-offline-<version>-<commit>.run.sha256
```

## check.sh：本地检查入口

```bash
bash check.sh
```

无命令行参数。从仓库根目录执行，运行语法检查命令、可选的 shellcheck、映射数组加载检查、`1.108.0` 版本查询、映射生成脚本帮助检查，以及 `tests/offline-install.sh`。任一步失败返回非零状态。没有安装 shellcheck 时仅跳过该项，不阻止其他检查。

## tests/offline-install.sh：安装回归检查

```bash
bash tests/offline-install.sh
```

无命令行参数。构造模拟载荷，在临时目录检查：CLI 残留时补装 Server、保留已有 CLI、完整安装跳过、不完整安装默认拒绝、显式强制重装、损坏压缩包和 commit 不匹配时拒绝，以及拒绝覆盖指向旧安装的符号链接。

测试还对比安装前后的 SHA-256，检查旧版本文件、已有旧版路径、设置、扩展及缓存索引保持不变。预期失败场景会打印错误日志，最终出现 `[DONE] Offline installation regression checks passed.` 表示通过。该脚本不需要网络或 makeself，不启动真实 Server，也不代替 Remote-SSH 实际连接验证。
