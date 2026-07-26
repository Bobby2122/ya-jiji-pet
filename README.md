# 鸭吉吉桌宠

一只不接入 AI、安静陪伴学习和工作的鸭吉吉桌面宠物。目前提供 Windows Electron 版与 macOS 原生版。

## 它会做什么

- 每天 6:00 后或当天首次启动时出现一颗新蛋，17:00 孵化。
- 蛋会在白天按已过去的孵化时间，从完整、开裂、探头逐渐变化；17:00 只播放最后的破壳并变成鸭吉吉，不会临时连播全部阶段。
- 拖拽鸭吉吉时会朝拖动方向走路；平时也会眨眼、歪头，安静很久后睡觉。
- 17:15–19:00 最多提醒一次吃晚饭，可以永久关闭。
- 每次孵化都会进入收藏库，重复异色也会作为独立个体保存。
- 完全离线，不使用 OpenAI API，不会不停弹出对话。

## 异色概率

| 皮肤 | 稀有度 | 概率 |
| --- | --- | ---: |
| 暖阳原色 | 普通 | 16.7% |
| 草莓奶 | 少见 | 16.7% |
| 薄荷汽水 | 少见 | 16.7% |
| 薰衣草梦 | 少见 | 16.7% |
| 星夜 | 稀有 | 16.7% |
| 虹彩 | 超稀有 | 16.7% |

六种颜色实际按相同权重抽取，每种都是 `1/6`；表中的 16.7% 为四舍五入显示。

## Windows 使用

支持 Windows 10 / 11 x64。最方便的方式是在仓库 Releases 下载：

- [Windows 最新安装版](https://github.com/bobby2122/ya-jiji-pet/releases/latest/download/DuckJiji-Pet-Windows-Setup.exe)
- [Windows 最新免安装版](https://github.com/bobby2122/ya-jiji-pet/releases/latest/download/DuckJiji-Pet-Windows-Portable.exe)
- [最新版发布页面与源码](https://github.com/bobby2122/ya-jiji-pet/releases/latest)

这三个地址固定指向最新 Release，以后发布新版本时不需要让朋友更换下载链接。

右键鸭吉吉可以查看孵化进度、收藏库、异色图鉴，预览皮肤与孵化动画，以及开关晚饭提醒和开机启动。首次运行未签名版本时，Windows 可能显示 SmartScreen 提示。

安装新版前，请先右键旧版鸭吉吉并选择“退出鸭吉吉”，再运行安装包。安装后可在右键菜单第一行确认当前版本；下一行会显示 Windows 识别到的分辨率、缩放率和可用桌面区域，方便排查多显示器或高 DPI 问题。

开发和构建说明见 [`electron/README.md`](electron/README.md)。

## macOS 使用

本地构建：

```bash
./build.sh
```

构建结果是 `outputs/鸭吉吉桌宠.app`。macOS 版使用 AppKit 原生实现，功能与 Windows 版一致。

## 上传 GitHub

仓库已经包含 `.gitignore`、MIT 源码许可证、素材声明和 Windows 自动构建工作流。首次上传可以运行：

```bash
git add .
git commit -m "Add Duck Jiji desktop pet"
git remote add origin https://github.com/你的用户名/duck-jiji-pet.git
git push -u origin main
```

推送到 `main` 后，GitHub Actions 会构建 Windows 文件并放在该次任务的 Artifacts 中。发布给朋友时创建版本标签：

```bash
git tag v0.3.4
git push origin v0.3.4
```

标签构建成功后，工作流会自动创建 GitHub Release 并附上安装版与免安装版。

## 仓库结构

```text
electron/                 Windows / Electron 应用
Sources/DuckPet/          macOS / AppKit 源码
assets/sprites/frames/    macOS 使用的最终动画帧
.github/workflows/        Windows 自动构建与发布
```

## 许可与声明

程序源代码采用 MIT License。角色名称、形象设定和视觉素材不包含在 MIT 授权中，详见 [`ASSETS-NOTICE.md`](ASSETS-NOTICE.md)。这是非商业个人同人原型；角色和原作相关权利归原权利方所有。
