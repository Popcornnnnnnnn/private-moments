# Private Moments 公开版交接说明

Last reconciled: 2026-05-03

## 当前状态

这是公开版候选目录，不是所有者的私有开发目录。

- 公开版目录：`private-moments-open-source/`
- 私有开发目录：`private-moments/`
- 当前公开版目标：v1.0-public 收口准备。
- 2026-05-03 已吸收最新私有开发快照中的 Share Extension、Smart Tags、AI summary v3、AI title auto-insert、moment text Markdown-like rendering、feature toggles 和 appearance 设置。

## 已完成的公开版清理

- 已从私有开发目录复制代码快照，但排除 `.git`、`.gsd/`、`server/.env`、`server/data/`、`server/.venv/`、`node_modules/`、build 产物和临时目录。
- 已移除个人 Tailscale exception。
- 默认 iOS bundle id 已改为 `dev.privatemoments.app`。
- XcodeGen 配置不再包含个人 Team ID。
- 真机安装脚本不再内置个人 iPhone 名称，必须通过 `PRIVATE_MOMENTS_DEVICE_NAME` 指定。
- 已加入 `LICENSE`、`SECURITY.md`、`CONTRIBUTING.md` 和 `docs/PUBLIC-RELEASE-TRACK.md`。

## 当前验证目标

公开版最小验证应包括：

```bash
npm run setup:local
npm run verify:server
cd ios && xcodegen generate
xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

真机安装需要显式指定设备：

```bash
PRIVATE_MOMENTS_DEVICE_NAME="Your iPhone" npm run ios:device
```

## 下一步

1. 在第二台干净 Mac 上完整跑一遍 `npm run setup:local`。
2. 针对 Share Extension 的 App Group signing 写更详细的新用户配置说明。
3. 补 GitHub Actions，至少覆盖 server typecheck/build、admin build 和 iOS generic build。
4. 做一次完整 backup/restore/export 恢复演练。
