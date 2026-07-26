# 鸭吉吉桌宠 Windows 版

Electron 实现的透明桌面宠物，不联网、不接入 OpenAI API，也不会主动不停说话。

发布构建面向 Windows 10 / 11 x64。

## 开发运行

需要 Node.js 22 和 pnpm 11：

```powershell
pnpm install
pnpm start
```

## 构建 Windows 安装包

```powershell
pnpm run check
pnpm run dist:win
```

结果位于 `dist/`：

- `DuckJiji-Pet-Windows-Setup.exe`：可选择安装目录的安装版。
- `DuckJiji-Pet-Windows-Portable.exe`：双击即用的免安装版。

应用未配置商业代码签名，因此首次下载时 Windows 可能显示 SmartScreen 提示。正式公开发布时建议购买代码签名证书并按 electron-builder 文档配置签名。

状态数据保存在 Electron 的用户数据目录中；卸载或换版本不会主动删除收藏。
