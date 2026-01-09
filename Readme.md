# 参考
- https://github.com/megastep/makeself 

# 脚本说明
+ download_all_release.sh
  - 用来下载所有的 Linux  版本的 vscode

# 使用方式
- 依赖 makeself 工具
  有网络的 Linux 环境执行 apt install makeself, 也可手动到 https://github.com/megastep/makeself/releases 下载安装最新版本
- 依赖 wget 1.16+
- 执行下载并打包，可以指定 vscode-server-linux 的 commit-id 下载指定版本
  ```bash
	./vscode-server-installer-allinone.sh -d [commit-id]
  ```
- 拷贝打包好的安装文件到离线环境，执行下面的命令安装
  ```
	./vscode-server-installer-offline.run
  ```

# 使用
+ 版本 与 commit_id 之间映射文件，一次性操作，可以复用已有的映射文件
  + 使用 download_all_release.sh 下载所有的 Linux 版本
    ```
    bash download_all_release.sh
    ```
  + 使用 get_product_commitid.sh 生成 commit_id 映射文件 vscode-version-commit.sh
    ```
    bash get_product_commitid.sh
    ```

+ 使用 vscode-server-downloader.sh 下载指定版本（依赖 vscode-version-commit.sh）
  或者是指定 commitid 的 vscode-server，并生成 .run 结尾的一键安装文件
  ```bash
  bash vscode-server-downloader.sh -d <version|commitid>
  ```

+ 在离线的 Linux 环境上执行
  ```bash
  bash vscode-server-installer-offline-allinone-1.99.3-17baf841131aa23349f217ca7c570c76ee87b957.run -i
  ```