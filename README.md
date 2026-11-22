# kkguai

**把 Windows 程序变成 Mac 原生窗口 —— 不用虚拟机，也不用整块远程桌面。**

[中文](#中文) · [English](#english)

> **下载 / Download:** [kkguai 0.1.1 · .dmg · Apple Silicon · macOS 14+](https://github.com/kkguai666/kkguai/releases/latest)

---

## 中文

kkguai 是一款 macOS 上的 RDP RemoteApp 客户端。它连接你已有的 Windows 电脑，只把需要的那几个程序窗口搬到 Mac 上：每个程序一个原生窗口、一个 Dock 图标，虚拟机、整屏远程桌面统统不需要。

### 为什么用它

- **像本地应用一样用 Windows 程序。** 没有「远程桌面」那块大窗口，只有一个一个的应用窗口，和你 Mac 上的其他窗口并排。
- **Retina 清晰显示。** 按 2 倍像素协商，文字锐利不发虚，和原生 Mac 应用放在一起也看不出差别。
- **中文输入无障碍。** 用 Mac 输入法正常打拼音，候选框在 Mac 上弹，选完的字直接落进远端程序。
- **光标会「变」。** 文本、链接、窗口边缘的光标形状和热点都跟随 Windows，点击位置所见即所得。
- **窗口随手拖。** 拖动、缩放都在 Mac 本地完成，松手后才同步给远端，手感跟本地窗口一致。
- **免费的 Parallels Coherence 式体验。** 不需要装 Windows、不需要买虚拟机授权，连一台现成的 Windows 电脑就行。

### 功能

| | |
|---|---|
| 单窗口 RemoteApp | 远端程序一个窗口 = Mac 一个原生窗口，不显示远端桌面 |
| 桌面模式 | 需要时也能把整个 Windows 桌面放进一个 Mac 窗口 |
| Retina / HiDPI | 200% 会话协商，1/2 点映射，2x 渲染 |
| Mac 输入法 | 中文、日文、韩文在 Mac 合成，以 Unicode 发送 |
| 远端光标 | 跟随 Windows 光标形状与热点 |
| Dock 与启动 | 每个远端程序独立 Dock 图标；Windows 11 风格开始菜单；支持 Spotlight / Launchpad |
| 多显示器 | 把 Mac 的显示器布局同步给远端，窗口可以跨屏拖动 |
| 快捷键 | Mac 键盘直通，左 Command 映射为 Ctrl，常用快捷键符合 Mac 习惯 |

### 系统要求

- macOS 14 或更高（当前发布包为 Apple Silicon）
- 一台开启了远程桌面（RDP）的 Windows 10 / 11 专业版电脑
- 两台机器之间网络可达（局域网、VPN 或 Tailscale 均可）

### 安装

1. 从 [Releases](https://github.com/kkguai666/kkguai/releases/latest) 下载 `kkguai-*-macos-arm64.dmg`。
2. 打开磁盘映像，把 `kkguai.app` 拖进「应用程序」，然后推出磁盘映像。
3. 发布包尚未经过 Apple 公证，首次打开前执行一次：

   ```bash
   xattr -dr com.apple.quarantine /Applications/kkguai.app
   ```

   然后正常双击打开（或右键 → 打开）。只需要做这一次。

### 构建

需要 Xcode Command Line Tools（Swift 5.9+）。

```bash
git clone https://github.com/kkguai666/kkguai.git
cd kkguai
./scripts/build-app.sh            # 构建并安装到 /Applications/kkguai.app
./scripts/build-app.sh --no-install   # 只构建到 build/kkguai.app
```

首次构建会自动调用 `scripts/build-freerdp.sh` 在 `build/deps/` 下编译 FreeRDP 和 OpenSSL。应用使用 ad-hoc 签名，从网络下载后如被 Gatekeeper 拦截，执行一次：

```bash
xattr -dr com.apple.quarantine /Applications/kkguai.app
```

### 许可

MIT，见 [LICENSE](LICENSE)。本项目基于 [Pstsc](https://github.com/D-opamin-e/pstsc)（MIT）修改而来，感谢原作者的工作。

---

## English

**Run Windows apps as native Mac windows — no virtual machine, no full remote desktop.**

kkguai is a RemoteApp (RDP) client for macOS. It connects to a Windows PC you already have and brings over only the apps you need: one native Mac window per program, one Dock icon each. No VM, no big "remote desktop" window.

### Why kkguai

- **Windows apps that feel local.** No full-desktop window — just individual app windows, side by side with your Mac apps.
- **Retina-sharp.** The session is negotiated at 2× pixels, so text stays crisp next to native Mac UI.
- **Input methods just work.** Compose Chinese, Japanese or Korean with your Mac input method; the candidate window appears on the Mac and finished text lands in the remote app.
- **Real cursor feedback.** Cursor shapes and hotspots (text, links, resize) follow the Windows side, so click positions match what you see.
- **Window dragging and resizing feel native.** Moves and resizes happen locally on the Mac and sync to the remote side when you let go.
- **A free Parallels Coherence-style experience.** No Windows install, no VM licence — just an existing Windows machine.

### Features

| | |
|---|---|
| Per-app windows | One remote program = one native Mac window; the remote desktop is never shown |
| Desktop mode | Optionally show the whole Windows desktop in a single Mac window |
| Retina / HiDPI | 200% session scaling with 2× rendering |
| Mac input method | CJK composition on the Mac, sent as Unicode |
| Remote cursors | Windows cursor shapes and hotspots |
| Dock & launching | A Dock icon per remote app; Windows 11-style Start menu; Spotlight / Launchpad support |
| Multi-monitor | Mac display layout is mirrored to the remote side; windows can move across screens |
| Keyboard | Mac keys pass through; left Command acts as Ctrl; familiar shortcuts keep working |

### Requirements

- macOS 14 or later (the current release is Apple Silicon)
- A Windows 10 / 11 Pro PC with Remote Desktop (RDP) enabled
- Network reachability between both machines (LAN, VPN or Tailscale)

### Install

1. Download `kkguai-*-macos-arm64.dmg` from [Releases](https://github.com/kkguai666/kkguai/releases/latest).
2. Open the disk image, drag `kkguai.app` into Applications, then eject the image.
3. The build is not notarized by Apple yet. Before the first launch, run once:

   ```bash
   xattr -dr com.apple.quarantine /Applications/kkguai.app
   ```

   Then open it normally (double-click, or right-click → Open). Only needed once.

### Build

Xcode Command Line Tools (Swift 5.9+) required.

```bash
git clone https://github.com/kkguai666/kkguai.git
cd kkguai
./scripts/build-app.sh                # build and install to /Applications/kkguai.app
./scripts/build-app.sh --no-install   # build only, into build/kkguai.app
```

The first build compiles FreeRDP and OpenSSL into `build/deps/` via `scripts/build-freerdp.sh`. The app is ad-hoc signed; if Gatekeeper blocks a downloaded copy, run:

```bash
xattr -dr com.apple.quarantine /Applications/kkguai.app
```

### License

MIT, see [LICENSE](LICENSE). Based on [Pstsc](https://github.com/D-opamin-e/pstsc) (MIT) — thanks to its authors.
