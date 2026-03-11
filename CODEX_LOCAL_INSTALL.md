# Codex 本地安装说明

## 一键安装（优先尝试在线）

```bash
cd /workspace/123
./install_codex_local.sh
```

默认安装目录：`~/.local/bin/codex`

## 当前环境网络受限时（推荐离线）

如果在线安装报 `403` / `Tunnel connection failed`，使用离线安装：

1. 在可联网机器下载包：
   ```bash
   npm pack @openai/codex
   ```
2. 把 `*.tgz` 拷到当前机器。
3. 执行：
   ```bash
   cd /workspace/123
   ./install_codex_local.sh --tarball ./openai-codex-<version>.tgz --skip-network
   ```

## 配置 PATH

```bash
export PATH="$HOME/.local/bin:$PATH"
codex --version
```
