# 参考
- https://github.com/megastep/makeself 

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