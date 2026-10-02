# LockRotate

[English](README.md) | 简体中文

一个 macOS 菜单栏小工具：把「系统设置 → 锁定屏幕 → 锁定时显示信息」里的那段文字（底层是 `LoginwindowText`），按你给的列表一条条换着显示。

## 功能

- 从 `.txt` 或 `.json` 文件导入，也可以在 App 里逐条添加、编辑。
- 按顺序或随机播放。随机是把整个列表过一遍再重新洗牌，不会连着出现同一条。
- 触发时机：定时（1 分钟到 24 小时）、Mac 唤醒时、屏幕解锁时、App 启动时。菜单栏面板里的「下一条」可以立刻换。
- 可以暂停自动轮换，暂停状态重启后还在。
- 可选「登录时自动打开」。
- 点菜单栏图标会打开一个面板，用锁屏预览卡片显示当前的锁屏文字，以及它在列表中的位置。
- 界面有中文和英文。

## 安装

### 下载预编译版

1. 在本仓库的 Releases 页面下载 `LockRotate-<版本>-macos.zip`，需要的话用旁边的 `.sha256` 文件核对（`shasum -a 256 -c LockRotate-<版本>-macos.zip.sha256`）。
2. 解压，把 `LockRotate.app` 拖进 `/Applications`。
3. 这个 App 是 ad-hoc 签名，**没有公证**，第一次打开 macOS 会拦截。两种放行办法：
   - 打开「系统设置 → 隐私与安全性」，往下找到 LockRotate，点「仍要打开」（macOS 15 及以后用这个办法；更早的系统右键点 App 选「打开」也行）；
   - 或者在终端里去掉隔离标记：
     ```sh
     xattr -dr com.apple.quarantine /Applications/LockRotate.app
     ```

### 从源码构建

需要 macOS 上的 Swift 6 工具链（Xcode 或命令行工具）。

```sh
scripts/build-app.sh          # 生成 build/LockRotate.app
scripts/package-release.sh    # 另外生成 build/LockRotate-<版本>-macos.zip 和 .sha256 文件
```

用 `VERSION=1.2.3` 可以改写进 App 的版本号。不需要开发者证书，用的是 ad-hoc 签名。

## 第一次使用

1. 点菜单栏图标，在面板里点「设置…」。
2. 打开「授权」页，点「授权…」（授权之前，面板里的主按钮也是「授权…」），系统会要一次管理员密码。
   装上的是一个很小的、root 所有的脚本，只能设置锁屏文字（见[安全模型](#安全模型)）。
   想用终端也行：在仓库里运行 `scripts/install.sh`，用你自己的账号运行，不要加 `sudo`。
3. 在「列表」页导入文件（或手动添加）。
4. 在「轮换」页选顺序和触发时机。

授权之前，App 只能显示当前文字，改不了。

## 列表格式

**文本**（`.txt`）：一行一条。行内写 `\n` 表示换行。空行和以 `#` 开头的行会被忽略。

```
# 以 # 开头的是注释
先喝口水，再继续。
记得眨眼，\n记得喝水，\n记得你可以休息。
```

**JSON**（`.json`）：字符串数组。（`{"quotes": [...]}` 这种对象也可以。）

```json
["先喝口水，再继续。", "记得眨眼，\n记得喝水，\n记得你可以休息。"]
```

导入时会整理：去掉控制字符，合并多余空行，去掉完全相同的重复项，每条最多保留 3 行、500 个字符（超出的部分被截掉，结尾加「…」）。有多少条被跳过、截短或当作重复去掉，App 会告诉你。

为什么限 3 行：多行文字在锁屏上是按行显示的，但内容多的时候，信息框需要上下滑动才能看全。

示例文件在 [`examples/quotes.txt`](examples/quotes.txt) 和 [`examples/quotes.json`](examples/quotes.json)（两个文件内容相同，共 12 条，是为这个项目写的）。

## 什么时候换

- **顺序**：「按顺序」从头到尾循环；「随机」把整个列表随机排一遍，播完再重新洗牌，新一轮不会从刚播完的那条开始。
- **定时**：每隔 N 分钟（默认 30）。
- **唤醒**：Mac 从睡眠中唤醒后约 3 秒。
- **解锁**：系统发出「屏幕已解锁」通知时。
- **启动**：App 启动时换一次（前提是已授权、没有暂停、且至少开了一种触发）。
- 自动触发如果离上一次不到 5 秒，会被忽略，因为唤醒后通常紧跟着就是解锁。面板里的「下一条」不受这个限制。
- 面板里的「暂停」会停掉上面所有自动触发，「下一条」仍然能用。

列表和设置存在 `~/Library/Application Support/LockRotate`。

## 安全模型

写锁屏文字需要 root，所以授权时会装一个 helper 脚本，再加一条 sudoers 规则：允许你的用户免密码运行这一个脚本，别的都不行。脚本从 stdin 读文字，限制在 2048 字节以内、合法 UTF-8、除换行外不含控制字符，除了写这段文字什么也不做。

代价是：以你的用户身份运行的任何进程，都能不经询问地改锁屏文字。通过这个 helper，它们做不了别的事。细节、怎么审计这个 36 行的 helper、怎么手动清理干净，都在 [SECURITY.md](SECURITY.md)。

## 卸载

- 在 App 里：设置 → 授权 → 「撤销授权…」（会要密码，同时清除锁屏文字），然后删除 `LockRotate.app`。
- 或者在仓库里运行 `scripts/uninstall.sh`（加 `--keep-text` 可以保留当前的锁屏文字）。
- 删除 App 之前，先关掉「登录时自动打开」。想连列表和设置一起删，删除 `~/Library/Application Support/LockRotate`。

## 测过什么

在 macOS 26.6.2（Apple Silicon）上手动测过：

- 写入 `LoginwindowText` 之后不需要 `killall cfprefsd` 就生效。多行文字在锁屏上按行显示。
- helper 的安装、写入、卸载；App 里的「授权…」和「撤销授权…」；「下一条」；定时 1 分钟触发；启动时自动轮换；暂停状态重启后保持。
- 解锁触发和 5 秒去重（用模拟的分布式通知测的）。
- 全部 205 个自动化测试通过（`swift test`）。

## 已知限制

- 只在 macOS 26.6.2、Apple Silicon 上测过。标称最低 macOS 13，但 13 到 15 和 Intel 机器都没试过。
- 真实的「锁屏 → 解锁」和「睡眠 → 唤醒」**没有**在真机上验证。解锁触发监听的是 `com.apple.screenIsUnlocked`，这是苹果没有文档化的通知，系统更新可能改掉或去掉它。定时、「下一条」和启动时轮换不依赖它。
- 「登录时自动打开」用的是 `SMAppService.mainApp`，要求 App 放在 `/Applications`。ad-hoc 签名的版本上它表现如何，没有测过。
- 预编译版没有公证（见上面的安装步骤）。
- 以你的用户身份运行的任何进程，都能通过 helper 改锁屏文字（只能改文字，且有长度和字符检查）。见 [SECURITY.md](SECURITY.md)。

## 开发

```sh
swift build
swift test
```

```
Sources/LockRotateCore/     列表导入、文字清洗、顺序/随机逻辑、设置与状态文件
Sources/LockRotateSystem/   helper 脚本（Resources/）、安装卸载封装、读取当前文字
Sources/LockRotateApp/      菜单栏面板、设置窗口、触发器
Tests/                      三个 target 的测试（Swift Testing）
scripts/                    build-app.sh、package-release.sh、install.sh、uninstall.sh
examples/                   示例列表
```

项目没有第三方依赖。`.github/workflows/` 里有 CI 和发布两个 workflow，还没有实际跑过。

## 致谢

「用 sudoers 放行的 helper 写 `LoginwindowText`、再从列表里轮换」的思路来自 [nikolazleo/LoginwindowText-Updater](https://github.com/nikolazleo/LoginwindowText-Updater)（MIT），「让锁屏上的一行字轮换」的想法来自 [Amorymeltzer/lockquote](https://github.com/Amorymeltzer/lockquote)。两者的代码和文字都没有拷贝，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 许可证

[MIT](LICENSE)
