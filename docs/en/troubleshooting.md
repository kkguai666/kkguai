---
title: kkguai troubleshooting
description: Fix connection, credential, RemoteApp, input method, Retina, multi-monitor and security problems in kkguai.
---

# kkguai troubleshooting

[中文](../troubleshooting.html) · **English**

Find your symptom below instead of reading top to bottom.

If you haven't installed it yet, start with the [install steps in the README](https://github.com/kkguai666/kkguai#install).

---

## Can't connect to the Windows PC

**First check that this Windows PC can be reached by Remote Desktop at all.** Try once with Microsoft's Windows App (formerly Microsoft Remote Desktop). If that can't connect either, the problem is Windows or the network, not kkguai.

Check each item:

1. **Windows edition**: Pro or Enterprise is required. Home cannot host RDP.
2. **Remote Desktop switch**: Settings → System → Remote Desktop → On. Or run this in an administrator PowerShell:

   ```powershell
   Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
   Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'
   ```

3. **Right address**: the LAN IP on a local network, a 100.x address on Tailscale. Don't enter `localhost`.
4. **Reachable**: on the Mac, `ping` or `nc -vz <address> 3389`. On Tailscale both machines must be online.
5. **Port**: 3389 by default. Corporate networks and cloud hosts may change it or block 3389.
6. **Router / firewall**: if you only use it on the LAN, don't map 3389 to the internet; across networks, use a VPN or Tailscale.

## "Wrong account or password"

- Account format: for a local account use `PCNAME\username` or `.\username`; for a domain account use `DOMAIN\username`.
- Microsoft account: first confirm on the PC itself that you can sign in to Remote Desktop with "username + PIN/password". Sometimes you need the Microsoft account email instead.
- **RDP does not accept a blank password.** Windows blocks network logon without a password by default; set a password on the account first.
- If the password has special characters, make sure your input method didn't insert full-width characters.

## Connects, then drops immediately, or keeps reconnecting

The most common cause: **the same account already has a desktop session.**

The RemoteApp "one window per program" mode needs the target account to have no signed-in desktop session. If that account is signed in:

- at the Windows PC itself (the console session), or
- over Remote Desktop from another machine (Windows App and the like),

kkguai can't connect, or connects and then gets kicked by the server.

What to do:

1. Sign out of that session (not just disconnect), or
2. choose "Sign Out Session and Connect" in kkguai, or
3. give kkguai its own account and import `single-session.reg` from the release to avoid multiple sessions.

## The app list is empty, or clicking an app does nothing

1. Confirm **`enable-remoteapp.reg` from the release was imported as administrator**, and that Windows was restarted. It allows programs that aren't registered as RemoteApps to run as windows.
2. Confirm the Remote Desktop settings on Windows don't restrict the program list.
3. On Windows, run `remote/diagnose.ps1` (as administrator) and paste the output into an issue. The script checks the RDP switch, the firewall, sessions and RemoteApp policy.

## Chinese/Japanese/Korean input doesn't work, or characters repeat

- Type with the Mac input method: the candidate window should appear on the Mac, and the chosen characters go to the remote program.
- Keep the remote Windows **English keyboard (en-US)** as the default input method, so the remote side doesn't compose the text a second time. If the remote only has an IME, add en-US in Windows Settings and make it the default.
- Confirm you're on 0.1.1 or later (earlier builds may lack proper Unicode input negotiation).
- If it only fails in one specific program, name the program and the input method in an issue.

## Text looks blurry

- kkguai uses 200% session scaling and 2× pixel rendering. Make sure the Mac display isn't in a scaled mode that changes the logical resolution (System Settings → Displays).
- On an external display, make sure the window is on the right screen, then reconnect once so the session negotiates the new display layout.
- Still blurry: attach a screenshot, the display model, the macOS version, and the resolution from About This Mac → Displays.

## Window drag stutters, or resizing leaves black edges

- 0.1.1 fixed the black bars on the right/bottom edge after a resize. Check the version in About kkguai first.
- Dragging and resizing happen locally on the Mac first and sync to the remote on release; if the window "jumps" after you let go, that's usually network latency, not rendering.
- With high latency, rule out Wi-Fi and the public internet first; a direct LAN link or Tailscale is usually steadier.

## Multi-monitor layout is wrong

- Arrange the Mac's displays before connecting (System Settings → Displays → Arrange).
- kkguai mirrors the Mac layout to the remote; if you change the layout after connecting, reconnect once.
- If windows can only stay on the primary display, attach the display count and a screenshot of the arrangement.

## Security

- **Never expose 3389 to the internet.** Use Tailscale, WireGuard or another VPN.
- Use a strong password on the remote account; never a blank one.
- RDP traffic itself is encrypted, but an exposed port invites scanning and brute force.
- kkguai keeps connection details only in your Mac's Keychain; nothing is uploaded to any server.

## Uninstall

```bash
rm -rf /Applications/kkguai.app
```

Connection profiles and Keychain entries can be removed by searching for `pstsc` in Keychain Access.

---

## Still stuck?

Open an [issue](https://github.com/kkguai666/kkguai/issues) with:

- macOS version and Mac model (Apple Silicon / Intel)
- Windows version (10/11, Pro/Home)
- How the machines are connected (LAN / VPN / Tailscale)
- kkguai version
- Steps to reproduce and screenshots; logs are in `~/Library/Logs/Pstsc/`
- The output of `diagnose.ps1` on Windows (remove passwords and other sensitive data first)
