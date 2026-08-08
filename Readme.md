# 参考
- https://github.com/megastep/makeself 

# 下载环境依赖(打包需要)
- 依赖 makeself 工具
  有网络的 Linux 环境执行 apt install makeself, 也可手动到 https://github.com/megastep/makeself/releases 下载安装最新版本
  - 下载安装包
    ```bash
    wget https://github.com/megastep/makeself/releases/download/release-2.7.1/makeself-2.7.1.run
    ```
  - 运行安装
    ```bash
    ./makeself-2.7.1.run
    mv makeself-2.7.1 /opt/makeself
    ```
  - 配置 PATH
    ```bash
    # vim ~/.bashrc
    export PATH="$PATH:/root/.local/bin:/opt/makeself"
    ```

- 依赖 curl 或 wget 1.16+
- 依赖 jq
- 注意打包环境与运行环境最好是匹配的系统环境

# 使用
+ 版本 与 commit_id 之间映射文件，一次性操作，可以复用已有的映射文件
  + 使用 download_all_release.sh 下载所有的 Linux 版本
    ```
    bash download_all_release.sh
    ```
    默认会读取已有的 vscode_version_commit.sh，已存在 commit 映射的版本会跳过下载，避免重复下载和解包提取。
    如需强制重新下载：
    ```
    bash download_all_release.sh --force
    ```
    支持并发下载和节流控制：
    ```
    bash download_all_release.sh --parallel 4
    bash download_all_release.sh --sleep-min 10 --sleep-max 30
    ```
  + 使用 get_product_commitid.sh 生成 commit_id 映射文件 vscode-version-commit.sh
    ```
    bash get_product_commitid.sh
    ```

+ 使用 vscode-server-downloader.sh 下载指定版本（依赖 vscode-version-commit.sh）
  或者是指定 commitid 的 vscode-server，并生成 .run 结尾的一键安装文件
  ```bash
  bash vscode-server-downloader.sh -d [version|commitid]
  ```
  下载的 CLI 和 Server tar 包会缓存到 .cache/vscode-server-downloader，同一 commit 再次打包时会直接复用缓存。
  如需忽略缓存重新下载：
  ```bash
  bash vscode-server-downloader.sh -d [version|commitid] --force-download
  ```

+ 在离线的 Linux 环境上执行
  ```bash
  ./vscode-server-offline-1.108.0-94e8ae2b28cb5cc932b86e1070569c4463565c37.run
  ```

+ 本地检查
  ```bash
  bash check.sh
  ```
