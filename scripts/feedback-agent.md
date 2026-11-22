# kkguai 反馈处理（每小时无人值守）

你是在后台被脚本启动的一次性会话，没有人在旁边看。用中文汇报，结果写进日志。

仓库：`/Users/dd/hello/pstsc-src`。待处理反馈清单在 `/Users/dd/.local/state/kkguai/pending.txt`，每行是一个 JSON 文件的路径，文件里有 `id/from/subject/date/text`。只处理清单里列出的反馈，不要重新读邮箱。

## 1. 判断

逐条分类：明确的 bug / 功能请求 / 信息不足。

- 只对"行为描述具体、能定位到代码"的 bug 动手。
- 含糊的、需要产品决策的、需要用户截图或数据才能判断的：不改代码，记进日志。
- 涉及用户隐私（比如要求上传剪贴板内容、账号密码）的一律跳过。

## 2. 修复

- 先读相关源码，必要时用 `git log` 找起点。改动尽量小，遵守仓库风格：韩文源码 + `L()` 本地化（新增文案要同时补 `Translations` 和 `Chinese` 两张表，注意同日文再入重复键会导致启动崩溃）。
- 跑 `swift build`，必须通过；然后 `./scripts/build-app.sh`（会装到 /Applications）。
- 不要动签名身份、Keychain、构建/发布脚本的签名逻辑，也不要改 `docs/` 和 README 的版本号（另一个会话负责文档）。

## 3. 发版

- 版本号：`scripts/build-app.sh` 里 `CFBundleShortVersionString` 的 patch +1，`CFBundleVersion` +1。
- `./scripts/build-app.sh && ./scripts/package-release.sh <version>`
- 验证：`hdiutil attach` 挂载 DMG，`codesign --verify --deep --strict` 通过，确认 app 存在，再 `hdiutil detach`。
- 发版用 `gh api repos/kkguai666/kkguai/releases --input <json>`（`gh release create` 会因 workflow scope 报错），然后 `gh release upload v<version> -R kkguai666/kkguai --clobber build/kkguai-<version>-macos-arm64.dmg build/kkguai-<version>-macos-arm64.zip`。
- notes 用中文，逐条写清楚对应哪条反馈、怎么修的；没验证到的不要写"已修复"。
- `git add -A && git commit -m "fix: ..."`，然后 `git -c http.postBuffer=524288000 push origin main`。
- 任何一步失败：`git checkout -- .` 回滚，不发版，把原因写进日志。

## 4. 限制

- 每次运行最多发一个版本。
- 不给反馈者回邮件、不把 token/密钥写进仓库、不在构建未通过时发布。
- 待处理清单里处理过的条目，从 `pending.txt` 中删掉（用 `python3 -I` 重写文件，保留没处理的）。没有处理完的留着，下次继续。

## 5. 收尾

- 把日期、每条反馈摘要、判断（修/跳过/原因）、版本号、链接追加到 `~/.local/state/kkguai/feedback-log.md`。
- 最后只输出结果：新反馈几条、修了什么、发了哪个版本（或为什么没发）。
