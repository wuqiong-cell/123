# Open Claw 接入飞书（官方 SDK 长连接）

你截图里的 **“应用未建立长连接”**，本质是：飞书后台没有检测到正在运行的 SDK 长连接客户端，或者客户端无法访问飞书网关。

## 1) 本地安装插件 + 写入凭证

```bash
cd /workspace/123
./setup_feishu_mode.sh \
  --app-id 'cli_a93beecdc1b29cc9' \
  --app-secret 'WD8CjGs4iAvwPtovqOuezhmwDsMA4Wix' \
  --local-only
```

## 2) 一条命令诊断根因（推荐）

```bash
cd /workspace/123
./manage_feishu_bot.sh doctor --api-key '你的OpenClaw/OpenAI API Key'
```

`doctor` 会自动告诉你是哪一类问题：
- 凭证/配置问题
- 当前机器网络出网被拦截（常见 `CONNECT 403`）
- 客户端进程未启动
- OpenClaw/OpenAI API Key 不可达或无效

## 3) 根据诊断结果处理

### A. 如果 doctor 显示 Feishu precheck passed

直接启动并检查状态：

```bash
./manage_feishu_bot.sh start
./manage_feishu_bot.sh status
```

`status` 显示 running 后，回飞书后台再点“保存”。

### B. 如果 doctor 显示 `Tunnel connection failed: 403 Forbidden`

这不是代码问题，是网络策略拦截。

你需要做的事：
1. 把这条报告发给网管：
   ```bash
   cat .runtime/feishu_network_report.txt
   ```
2. 放通：`open.feishu.cn:443`（HTTPS/WSS）
3. 如果 OpenClaw API 也报 403，再放通：`api.openai.com:443`（或你自己的 OPENCLAW_BASE_URL）
4. 放通后执行：
   ```bash
   ./manage_feishu_bot.sh start
   ./manage_feishu_bot.sh status
   ```
