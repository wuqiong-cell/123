# Open Claw 安装说明

## 纯本地安装（推荐当前环境）

```bash
cd /workspace/123
./install_local_plugins.sh
```

安装位置：`${CODEX_HOME:-$HOME/.codex}/skills/open-claw`

## 官方在线安装（网络可用时）

```bash
python /opt/codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo openai/skills \
  --path skills/.curated/open-claw
```

## 当前环境问题

如果你看到 `Tunnel connection failed: 403 Forbidden`，说明出网被代理策略拦截。
可先走本地安装，等网络放通后再切换官方在线安装。
