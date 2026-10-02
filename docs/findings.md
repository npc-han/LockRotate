# M0 实测记录（macOS 26.6.2，2026-10-01）

在真机上实测 `LoginwindowText`，环境：Apple Silicon，macOS 26.6.2。

| 项 | 结论 |
|---|---|
| 写入方式 | `sudo /usr/bin/defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText -string "<text>"` 成功；写入后 plist 为 `root:wheel 644` |
| 是否需要 `killall cfprefsd` | **不需要**。写入后普通用户 `defaults read` 立即读到新值，所以 helper 不做 killall |
| 免提权读取当前文字 | 可以：`defaults read /Library/Preferences/com.apple.loginwindow LoginwindowText`（plist 644） |
| 换行 | 真实换行（`\n`）保留，锁屏界面按行显示 |
| 长度 | 5 行（含一行 100 位数字、一行约 40 个汉字）全部显示；内容较多时信息框需要上下滑动才能看全。因此默认限制保持保守：最多 3 行、500 字符（均为可配置参数） |
| 本机原状 | 测试前 `LoginwindowText` 与 `DisableLoginwindowText` 两个键都不存在；测试后已用 `defaults delete` 恢复 |
| 系统设置入口 | 系统设置 → 锁定屏幕 →「锁定时显示信息」+「设定…」，即此键 |

未实测：锁屏通知（`com.apple.screenIsLocked/Unlocked`）的触发时机，留到 M4。
