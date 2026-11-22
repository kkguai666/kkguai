# kkguai

把远端 Windows 电脑上的程序窗口，直接显示成 Mac 上的原生窗口（RDP RemoteApp，类似 Parallels 的 Coherence 模式）。不需要在 Mac 里装虚拟机，连上已有的 Windows 电脑就行。

本项目基于 [Pstsc](https://github.com/D-opamin-e/pstsc)（MIT 许可）修改而来，应用名改为 **kkguai**。

## 主要功能

**窗口**
- 远端 Windows 程序的一个窗口，对应 Mac 上的一个原生窗口，不显示远端桌面
- Retina / HiDPI：按 2 倍像素协商，文字清晰不发虚
- 拖动窗口四边即可调整大小，松手后把新位置和尺寸报给远端
- 支持桌面模式：把整个远端桌面放进一个 Mac 窗口

**输入**
- Mac 键盘直通远端，快捷键跟随 Windows 习惯（左 Command 当 Ctrl）
- 中文输入：在 Mac 上用拼音等输入法合成，选好的字以 Unicode 发给远端
- 远端光标形状和热点跟随 Windows 光标（I 形、手形、缩放等）

**Dock 与启动**
- 每个远端程序在 Dock 里有独立图标，点击切换、右键管理
- Windows 11 风格的开始菜单（搜索、固定应用、最近应用、电源）
- 远端应用注册到 Spotlight / Launchpad

## 构建

需要 macOS 14+、Xcode Command Line Tools（Swift）。

```bash
./scripts/build-app.sh          # 构建并安装到 /Applications/kkguai.app
./scripts/build-app.sh --no-install   # 只构建
```

首次构建会调用 `scripts/build-freerdp.sh` 在 `build/deps/` 下编译 FreeRDP 和 OpenSSL。

## 许可

MIT，见 [LICENSE](LICENSE)。原始项目为 [Pstsc](https://github.com/D-opamin-e/pstsc)，版权归其贡献者所有。
