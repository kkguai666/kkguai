# kkguai 排障

按「症状」找，不要从头读。

如果你还没装好，先看 [README 的安装步骤](https://github.com/kkguai666/kkguai#安装)。

---

## 连不上 Windows 电脑

**先确认这台 Windows 本身能被远程桌面连上。** 用微软的 Windows App（原 Microsoft Remote Desktop）试一次；如果它也连不上，问题在 Windows 或网络，不在 kkguai。

逐项检查：

1. **Windows 版本**：需要专业版或企业版。家庭版不能作为 RDP 主机。
2. **远程桌面开关**：设置 → 系统 → 远程桌面 → 打开。或在管理员 PowerShell 运行：

   ```powershell
   Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
   Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'
   ```

3. **地址对不对**：局域网用内网 IP；Tailscale 用 100.x 地址；不要填 `localhost`。
4. **网络可达**：在 Mac 上 `ping` 或 `nc -vz <地址> 3389`。Tailscale 里两台机器都要在线。
5. **端口**：默认 3389。公司网络或云主机可能改了端口或封了 3389。
6. **路由器/防火墙**：只在局域网用，就别把 3389 映射到公网；跨网请用 VPN 或 Tailscale。

## 提示账号或密码错误

- 账号格式：本地账号用 `电脑名\用户名` 或 `.\用户名`；域账号用 `域\用户名`。
- 微软账号：先在本机确认能用「用户名 + PIN/密码」登录远程桌面。有时需要改用 Microsoft 账户邮箱。
- **空密码不能用于 RDP**。Windows 默认禁止空密码网络登录，请先给账号设置密码。
- 密码里如果有特殊字符，确认输入法没有把全角字符打进去。

## 连上后马上断开，或者一直重连

最常见的原因：**同一个账号已经有一个桌面会话**。

RemoteApp 的「按程序开窗口」模式需要目标账号没有已登录的桌面会话。如果这个账号正登录在：

- Windows 电脑前面（控制台会话），或
- 另一台机器上的远程桌面（Windows App 等），

kkguai 就连不上，或者连上后被服务器踢掉。

处理方式：

1. 在那个会话里注销（不是断开），或
2. 在 kkguai 里使用「注销现有会话后连接」，或
3. 给 kkguai 单独用一个账号，并导入 Release 里的 `single-session.reg`，避免多会话。

## 程序列表是空的，或点了没反应

1. 确认 Release 里的 **`enable-remoteapp.reg` 已经以管理员权限导入**，并且 Windows 已重启。它会允许未注册为 RemoteApp 的程序以窗口方式运行。
2. 确认 Windows 的远程桌面设置里没有限制程序列表。
3. 在 Windows 上运行 `remote/diagnose.ps1`（管理员），把输出贴到 issue 里。脚本会检查 RDP 开关、防火墙、会话和 RemoteApp 策略。

## 中文输入法打不出字，或出现重复的字

- 用 Mac 输入法打字：拼音候选框应该出现在 Mac 上，选完的字进入远端程序。
- 远端 Windows 保持 **英文键盘（en-US）** 为默认输入法，避免远端再合成一遍。如果远端只剩中文输入法，请在 Windows 设置里添加 en-US 并设为默认。
- 确认用的是 0.1.1 或更新的版本（早期版本可能没有正确的 Unicode 输入协商）。
- 如果只有在某个特定程序里失效，在 issue 里写明程序名和输入法。

## 字发虚、不清晰

- kkguai 按 200% 会话缩放、2× 像素渲染。请确认 Mac 的显示器没有处在会改变逻辑分辨率的缩放模式（系统设置 → 显示器）。
- 如果是外接显示器，确认窗口在正确的屏幕上，然后重新连接一次，让会话按新的显示器布局协商。
- 仍然模糊：附上截图、显示器型号、macOS 版本和「关于本机 → 显示器」里的分辨率。

## 窗口拖动卡、缩放有黑边

- 0.1.1 修复了缩放后右/下边缘的黑条。先在「关于 kkguai」里确认版本。
- 拖动和缩放先在 Mac 本地完成，松手后才同步给远端；如果松手后窗口「跳」一下，通常是网络延迟，不是渲染问题。
- 网络延迟高时，先排除 Wi-Fi 和跨公网；局域网直连或 Tailscale 通常更稳。

## 多显示器不对

- 连接前先把 Mac 的显示器排列好（系统设置 → 显示器 → 排列）。
- kkguai 会把 Mac 的布局同步给远端；连接后再改布局，需要重新连接一次。
- 如果窗口只能停在主屏，附上显示器数量和排列截图。

## 安全建议

- **不要把 3389 直接暴露在公网。** 用 Tailscale、WireGuard 或其他 VPN。
- 给远程账号设置强密码；不要用空密码。
- RDP 传输本身是加密的，但暴露端口会带来扫描和爆破风险。
- kkguai 只保存连接信息在你本机的钥匙串里；不会上传到任何服务器。

## 卸载

```bash
rm -rf /Applications/kkguai.app
```

连接配置和钥匙串条目可以在「钥匙串访问」里搜索 `pstsc` 删除。

---

## 还解决不了？

开一个 [issue](https://github.com/kkguai666/kkguai/issues)，附上：

- macOS 版本、Mac 型号（Apple Silicon / Intel）
- Windows 版本（10/11，专业版/家庭版）
- 网络方式（局域网 / VPN / Tailscale）
- kkguai 版本
- 复现步骤和截图；日志在 `~/Library/Logs/Pstsc/`
- Windows 上 `diagnose.ps1` 的输出（注意先删掉密码等敏感信息）
