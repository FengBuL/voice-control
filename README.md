<p align="center"><img src="Assets/VoiceIcon.png" width="128" alt="Voice app icon"></p>
<h1 align="center">Voice</h1>
<p align="center">外接显示器的声音，随手调节 · Monitor volume at your fingertips</p>
<p align="center"><a href="https://github.com/FengBuL/voice-control/releases">下载 / Download</a> · <a href="docs/README.en.md">English</a> · <a href="https://github.com/FengBuL/voice-control/issues">反馈</a></p>

当 HDMI 显示器有内置音箱、Mac 的系统音量滑块却无法调节时，Voice 提供菜单栏滑块与静音。软件音量在本机实时调节送往当前声音输出的信号；支持的显示器也可尝试 DDC/CI 硬件音量控制。

**0.3.0 Beta：Apple Silicon · macOS 14.2+ · 中文界面。** 当前发布包使用临时签名，尚未经过 Apple Developer ID 签名与公证，首次打开可能需要在“隐私与安全性”中允许。已验证设备与限制见下文。

## 下载与安装

1. 前往 [Releases](https://github.com/FengBuL/voice-control/releases)，下载最新的 `Voice-版本-macOS-arm64.dmg`。
2. 打开 DMG，将 **Voice** 拖入 **Applications（应用程序）**，再从应用程序文件夹启动。
3. 若 macOS 提示开发者无法验证，先尝试打开一次，再到“系统设置 → 隐私与安全性”按 [Apple 说明](https://support.apple.com/102445) 查看“仍要打开”。仅在确认来源后操作，无需关闭系统安全检查。
4. 从菜单栏的扬声器图标打开 Voice。菜单栏应用启动后通常不显示 Dock 图标。

也提供 ZIP 和 SHA-256 校验文件。卸载时退出 Voice，再删除应用；无需移除音频驱动。

## 使用

1. 在“系统设置 → 声音 → 输出”选择显示器。
2. DDC 音量不可用时，点击 **启用软件音量**，允许 macOS 的系统音频访问请求。
3. 播放声音，拖动滑块、按 ±5 或点击静音，检查实际听感。每次启用软件音量的初始值为 30%。
4. 可选开启“设置与连接测试 → 接管键盘音量键”。此项需要辅助功能权限；Option + Shift 可按 1% 微调。
5. 更换 HDMI / USB-C 转 HDMI 连接或系统声音输出后，重新启用软件音量。

显示器实体音量决定最大响度。停止软件音量或退出 Voice 后，衰减结束，声音可能恢复原始响度；建议先暂停播放，或将显示器实体音量保持在舒适水平。

软件模式使用系统当前声音输出，不限定 USB-C 转 HDMI；HDMI 直连使用相同处理路径。系统控制中心的 HDMI 滑块可能继续灰色，请使用 Voice 面板。软件模式不会修改系统默认输出设备。

## 功能

- 原生 SwiftUI 面板与 AppKit 菜单栏，macOS 风格图标。
- 软件音量滑块、±5、静音与恢复，短暂增益渐变。
- 本机 Core Audio process tap 与私有聚合设备，排除自身播放，避免反馈回路。
- 无录音文件、音频上传、第三方音频驱动、广告或遥测。[隐私说明](docs/PRIVACY.md)
- 默认输出切换时停止软件通道；停止或退出时清理通道。
- DDC/CI 检测、写入后读回核对，以及可选只写诊断模式。
- 只写模式的百分比代表发送目标，需通过实体菜单或实际声音确认效果。

## 验证范围与兼容性

| 项目 | 当前结果 |
| --- | --- |
| USB-C 转 HDMI → BenQ EW2780Q | 用户实测软件音量与静音有效 |
| 两个现有 BenQ HDMI 音频设备 | 通道创建和清理预检查通过，无捕获启动 |
| HDMI 直连 | 代码使用相同路径，实际播放待更多接线验证 |
| 音频格式 | 当前接受双声道 32-bit float PCM，输入输出采样率一致 |
| macOS | 最低构建目标 14.2；实际验证在开发机 macOS 27.0 |
| 键盘音量键 | 已实现，实际兼容性仍需更多验证 |
| DDC 硬件音量 | 依赖设备与连接，本机仍返回空回复 |

Intel Mac、环绕声、受保护内容、延迟和更广泛设备组合尚未验证。Voice 不承诺所有显示器的硬件音量控制可用。

## 常见问题

**只有软件百分比改变，声音没变？** 确认已启用软件音量、系统声音输出选对设备、已授权系统音频访问，并用普通播放器验证。DDC 只写模式需要单独核对实际效果。

**已拒绝音频访问权限？** 在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许 Voice，退出并重新启动，再启用软件音量。系统版本不同，设置名称可能略有差异。

**切换连接后无效？** 选择新的系统声音输出，然后重新启用软件音量。

**想让硬件音量直接变化？** 开启显示器 DDC/CI，再重新检测。转接链和显示器固件可能影响 DDC；软件音量可以在当前受支持的音频配置下调节播放信号。

## 从源码构建

需要 Apple Silicon Mac、macOS 14.2+、Apple Command Line Tools 与 Python 3。

```sh
git clone https://github.com/FengBuL/voice-control.git
cd voice-control
./test.sh
./build.sh
open build/Voice.app
```

`./scripts/package.sh` 构建 DMG、ZIP、安装说明与 SHA-256 文件，输出到 `release/`。构建采用临时签名；公开发行的 Developer ID 签名与公证仍待配置。

`build/Voice.app/Contents/MacOS/Voice --audio-preflight` 只检查私有音频通道创建与清理，不启动捕获。`--smoke-test` 检查菜单栏和面板启动。项目内 VFS overlay 用于规避部分 Command Line Tools 的重复 Swift 模块映射，不修改系统 SDK。

测试覆盖异常音量回复、量程换算、设备标识、辅助进程失败与超时、DDC 报文，以及音频衰减、静音、平面声道与限幅。

## 反馈与许可

欢迎在 [Issues](https://github.com/FengBuL/voice-control/issues) 提交 macOS 版本、Mac / 显示器型号、线材连接方式、声音输出名称和复现步骤。请省略硬件序列号、账号与私人信息。

MIT 许可，见 [LICENSE](LICENSE)。DDC 后端来自 [m1ddc](https://github.com/waydabber/m1ddc)，固定上游提交和本地修改见 [UPSTREAM.md](Vendor/m1ddc/UPSTREAM.md)，保留其 MIT 许可。DDC 使用非公开显示接口，系统更新后的兼容性需重新确认。软件音量使用 [Apple 官方 Core Audio tap API](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)。
