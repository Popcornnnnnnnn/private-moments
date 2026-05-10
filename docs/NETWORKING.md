# 网络接入配置

Private Moments 不绑定任何特定网络供应商。iOS App 只需要一个可访问的 Mac server URL；这个 URL 可以来自本地网络、Tailscale、Cloudflare Tunnel、反向代理或其他私有 VPN。

## 推荐路径

### 1. 本地开发和模拟器

这是最短路径，适合先确认项目能跑起来：

```bash
npm run setup:local
npm run server:dev
npm run ios:simulator
```

默认 server URL：

```text
http://127.0.0.1:3210
```

### 2. 真实 iPhone：私有网络优先

真实 iPhone 不能访问 Mac 的 `127.0.0.1`。你需要给 iPhone 一个能连到 Mac server 的地址：

- 同一局域网：`http://<mac-lan-ip>:3210`
- Tailscale 或其他私有 VPN：`https://<your-private-host>` 或 `http://<private-ip>:3210`
- 其他自管 HTTPS 入口：你自己维护的受保护 endpoint

如果使用明文 HTTP，server 需要监听非 localhost 地址：

```env
HOST=0.0.0.0
PORT=3210
```

公开仓库不会内置任何 tailnet 名称、个人 IP、域名或设备名。

### 3. Cloudflare Tunnel：可选高级路径

Cloudflare Tunnel 适合想给 iPhone 一个 HTTPS remote URL、但不想让 Mac 直接暴露公网端口的用户。它不是 Private Moments 的必需组件。

如果你使用 Cloudflare Tunnel：

- 使用自己的 Cloudflare 账号和域名。
- 给 endpoint 加 Cloudflare Access、allowlist、gateway auth 或其他访问控制。
- 优先只放行 iOS 同步所需 API。
- 不建议在没有额外保护时暴露完整 Admin UI。

建议放行的最小 API 面：

```text
/api/v1/health
/api/v1/auth/login
/api/v1/sync
/api/v1/media/*
/api/v1/checkin-media/*
/api/v1/ai/media-summary
/api/v1/admin/status
```

`/admin/` 是 Mac-local 运维界面，默认应保留在本机或私有网络里。

## 本地覆盖配置

复制示例文件：

```bash
cp .env.local.example .env.local
```

常用项：

```env
PRIVATE_MOMENTS_DEVICE_NAME="Your iPhone"
PRIVATE_MOMENTS_DEVICE_SERVER_URL=https://your-private-server.example
PRIVATE_MOMENTS_FALLBACK_SERVER_URL=https://your-fallback-server.example
PRIVATE_MOMENTS_DEVELOPMENT_TEAM=YOURTEAMID
PRIVATE_MOMENTS_IOS_BUNDLE_ID=dev.yourname.privatemoments
PRIVATE_MOMENTS_IOS_SHARE_BUNDLE_ID=dev.yourname.privatemoments.share
PRIVATE_MOMENTS_IOS_APP_GROUP=group.dev.yourname.privatemoments
```

`.env.local` 会被 `npm run ios:simulator` 和 `npm run ios:device` 读取。脚本会生成 ignored 的 `ios/Config/Local.xcconfig`，用于覆盖公开默认的 iOS bundle id、App Group、Team ID 和 fallback URL。

如果你已经在真实 iPhone 上安装过 Private Moments，并希望保留原有 app container 与 App Group 数据，不要随意改变这些值：

- `PRIVATE_MOMENTS_IOS_BUNDLE_ID`
- `PRIVATE_MOMENTS_IOS_SHARE_BUNDLE_ID`
- `PRIVATE_MOMENTS_IOS_APP_GROUP`

## App 内配置模型

iOS App 的同步模型是：

1. 用户在 Settings 里配置 `Server URL`。
2. App 先尝试这个 URL。
3. 如果 build 里注入了 `PRIVATE_MOMENTS_FALLBACK_SERVER_URL`，App 会把它作为额外候选。
4. 网络级失败或 route-missing 响应会尝试下一个候选；认证失败和业务错误不会被静默跳过。

这让开源用户可以自由选择网络层，而不需要修改同步协议或 server 代码。
