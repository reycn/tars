# Tars

![Tars banner](banner.zh-CN.svg)

把 iPhone 变成你的智能体的脸。灵感来自《星际穿越》。

[English](../README.md) · **中文**

把一台闲置的 iPhone 变成编程智能体的常亮状态面板。纯黑屏幕上的两只像素眼睛，让你隔着房间就能看出 Claude Code、Codex、opencode 或 pi 正在思考、等你批准、已完成，还是空闲。

| 等待 | 工作中 | 待批准 | 已完成 |
|---|---|---|---|
| <img src="../themes/bit/waiting.png" width="220"> | <img src="../themes/bit/working.png" width="220"> | <img src="../themes/bit/approval.png" width="220"> | <img src="../themes/bit/completed.png" width="220"> |

<img src="demo.gif" width="320" alt="Tars 状态切换演示">

## 你会得到什么

- **iPhone 应用**：全屏像素风脸孔，保持常亮，自动横竖屏，AMOLED 友好（背景永远是纯黑，状态由字形和像素颜色表达）。
- **Mac 菜单栏应用**：无需账号。它监听智能体的生命周期钩子，归纳为一个状态，通过 Bonjour 在局域网内推送给已配对的手机。
- **钩子而非日志抓取**：与 [codestatus](https://github.com/henriquegpb/codestatus) 相同的思路。Claude Code、Codex、opencode 和 pi 在每个生命周期事件上调用一个极小的钩子脚本，除此之外不监视任何东西。
- **详情行**：眼睛下方显示当前工具、待回答的问题或最后一条助手消息，最多两行。
- **配对**：Mac 上显示六位配对码，手机输入一次即可。

## 快速开始

1. **Mac**：构建并安装菜单栏应用（或使用 Release 构建）。

   ```zsh
   xcodebuild -project Tars.xcodeproj -scheme TarsMac -configuration Release -derivedDataPath .build/mac build
   cp -R .build/mac/Build/Products/Release/TarsMac.app /Applications/Tars.app && open /Applications/Tars.app
   ```

2. **连接智能体**：在 Mac 应用中打开 设置（⌘,）→ *Agents*，打开 Claude Code、Codex、opencode 或 pi。Codex 还需要你在 Codex 内运行一次 `/hooks` 并信任 Tars 的条目。

3. **iPhone**：用 Xcode 打开 `Tars.xcodeproj`，在 Signing & Capabilities 里选择你的团队，选中手机，运行。弹出提示时允许“本地网络”访问。

4. **配对**：如果尚未配对，手机启动两秒后会弹出 PIN 输入框。从 Mac 的设置窗口读取配对码并输入，之后会记住。

新开一个智能体会话，眼睛就会动起来。在第 2 步之前已经打开的会话仍使用旧的钩子集，需重启才会生效。

## 工作原理

```
Claude Code / Codex / opencode / pi ──钩子──▶ ~/.tars/bin/tars-hook ──本机 17894──▶ Tars.app ──Bonjour/TCP 17893──▶ iPhone
```

**钩子**（[Mac/hook.py](../Mac/hook.py)）。从 stdin 读取一条 JSON 载荷，投影为哈希后的会话键、归一化状态和一行裁剪后的详情，在 50 ms 预算内推送到 `127.0.0.1:17894`。它永远以 0 退出，并在 Claude Code 中以 `async` 方式注册，因此绝不会阻塞或拖垮智能体。

**安装器**（[Mac/install-hooks.py](../Mac/install-hooks.py)）。按智能体各放一份钩子到 `~/.tars/bin/`（路径无空格：Codex 会按空白分割命令；对会丢弃钩子参数的智能体，文件名本身携带智能体名），再按各自的方式接入：

| 智能体 | 接入位置 | 注册形式 |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | `async` 命令钩子条目 |
| Codex | `~/.codex/hooks.json` | 命令钩子条目，需用 `/hooks` 信任 |
| opencode | `~/.config/opencode/plugin/tars.js` | [插件](../Mac/opencode-plugin.js)（`event`、`chat.message`、`tool.execute.before`、`permission.ask`） |
| pi | `~/.pi/agent/extensions/tars.ts` | [扩展](../Mac/pi-extension.ts)（`session_start`、`before_agent_start`、`tool_call`、`message_end`、`agent_end`、`session_shutdown`） |

对于走 JSON 配置的两个智能体，归属判断依据是命令路径完全相等，因此绝不会碰用户自己的钩子；每次写入前都会在原文件旁边做备份。对于 opencode 和 pi，Tars 只拥有自己的那一个文件，移除时也只删这一个；旧版 Tars 留下的副本会被视作未开启，重新打开开关即可刷新。两个适配器都把各自智能体的事件翻译成钩子已经在 Claude Code 上读取的那套载荷，因此状态映射始终只存在于 `hook.py`。

```zsh
/usr/bin/python3 Mac/install-hooks.py install          # 全部智能体
/usr/bin/python3 Mac/install-hooks.py remove codex     # 单个智能体
/usr/bin/python3 Mac/install-hooks.py status
```

**状态模型。** 事件映射到手机上的四种状态，多个活动会话之间的优先级为：待批准 → 工作中 → 已完成 → 等待。

| 事件 | 状态 |
|---|---|
| SessionStart、StopFailure、Notification(idle_prompt) | 等待 |
| UserPromptSubmit、PreToolUse、PostToolUse、PostToolUseFailure、PermissionDenied、ElicitationResult、Pre/PostCompact | 工作中 |
| PermissionRequest、Notification(permission_prompt)、Elicitation，以及 `AskUserQuestion` / `ExitPlanMode` 的 PreToolUse | 待批准 |
| Stop | 已完成（保持 5 秒） |
| SessionEnd | 移除该会话 |

由于钩子不提供存活查询，静默 30 分钟的会话会被过期移除。你中断的一轮对话会保持最后状态直到你再次输入，因为 Claude Code 的 `Stop` 钩子在取消时不会触发。

**传输。** Mac 通过 Bonjour 广播 `_tars._tcp`。手机连接后首行发送 `{"code":"123456"}`，随后接收按行分隔的 JSON 快照：服务端会话 UUID、单调递增序号、状态、事件源是否可用、心跳间隔、详情。配对码错误会收到 `{"error":"unpaired"}` 并被断开。活动时每 20 秒一次心跳，空闲时 120 秒。手机采用有上限的退避重连，进入后台时断开。

**隐私。** 经过套接字和局域网的内容只有：会话 id 的 SHA-256 前缀、状态词，以及一行详情文本（工具名加其描述/命令/路径、待回答的问题，或最后一条助手消息，≤160 字符）。不会写入磁盘。如果你不希望任务文本出现在手机上，详情行只是 `hook.py` 里的一个函数。

## 主题

在 设置 → *Style* 里选择眼睛样式。所有主题都是原创像素画，来自 [iOS/Theme.swift](../iOS/Theme.swift) 中的 12×12 位图；不使用任何受版权保护的图片，名字只是致敬。选择主题会同时切换到它的配色，你仍可覆盖。

**Eva** —— 斜切的细眼，工作时亮成绿色，待批准时是空瞳的凝视。

| 等待 | 工作中 | 待批准 | 已完成 |
|---|---|---|---|
| <img src="../themes/eva/waiting.png" width="220"> | <img src="../themes/eva/working.png" width="220"> | <img src="../themes/eva/approval.png" width="220"> | <img src="../themes/eva/completed.png" width="220"> |

**Pika** —— 带高光的圆黄眼，待批准时是闪电，完成时是星光。

| 等待 | 工作中 | 待批准 | 已完成 |
|---|---|---|---|
| <img src="../themes/pika/waiting.png" width="220"> | <img src="../themes/pika/working.png" width="220"> | <img src="../themes/pika/approval.png" width="220"> | <img src="../themes/pika/completed.png" width="220"> |

**Miku** —— 带高光的青色大眼，工作时是音符，待批准时睁大凝视，完成时闪光。

| 等待 | 工作中 | 待批准 | 已完成 |
|---|---|---|---|
| <img src="../themes/miku/waiting.png" width="220"> | <img src="../themes/miku/working.png" width="220"> | <img src="../themes/miku/approval.png" width="220"> | <img src="../themes/miku/completed.png" width="220"> |

**Naruto** —— 护额线下的坚定眼神，工作时是查克拉漩涡，待批准是三勾玉环，完成时眯眼笑。

| 等待 | 工作中 | 待批准 | 已完成 |
|---|---|---|---|
| <img src="../themes/naruto/waiting.png" width="220"> | <img src="../themes/naruto/working.png" width="220"> | <img src="../themes/naruto/approval.png" width="220"> | <img src="../themes/naruto/completed.png" width="220"> |

**Xiaohei** —— 竖瞳圆猫眼；工作时眯起，待批准时睁大变金色，完成时是满足的弧线。

| 等待 | 工作中 | 待批准 | 已完成 |
|---|---|---|---|
| <img src="../themes/xiaohei/waiting.png" width="220"> | <img src="../themes/xiaohei/working.png" width="220"> | <img src="../themes/xiaohei/approval.png" width="220"> | <img src="../themes/xiaohei/completed.png" width="220"> |

**Dora** —— 椭圆大眼，空心瞳孔会转：静止时居中，工作时向下看，待批准时睁大，完成时是月牙。

| 等待 | 工作中 | 待批准 | 已完成 |
|---|---|---|---|
| <img src="../themes/dora/waiting.png" width="220"> | <img src="../themes/dora/working.png" width="220"> | <img src="../themes/dora/approval.png" width="220"> | <img src="../themes/dora/completed.png" width="220"> |

**Snoopy** —— 小豆豆眼；工作时挑眉，待批准时惊讶的眉毛，完成时闭眼笑。

| 等待 | 工作中 | 待批准 | 已完成 |
|---|---|---|---|
| <img src="../themes/snoopy/waiting.png" width="220"> | <img src="../themes/snoopy/working.png" width="220"> | <img src="../themes/snoopy/approval.png" width="220"> | <img src="../themes/snoopy/completed.png" width="220"> |

新增主题：在 `Theme` 里加一个 case、五张位图和一个配色预设，再把图片放到 `themes/<name>/`。

## 设置

**iPhone**（点击屏幕，再点 ⚙）：

- *配对码*：Mac 上的六位数字。
- *Style*：眼睛主题（Bit、Eva、Pika、Miku、Naruto、Xiaohei、Dora、Snoopy）。
- *颜色*：预设 Terminal Green、Windows Blue、Techno White，或自定义每个状态的颜色。所有预设中“待批准”都保持暖色，以便一眼识别。
- *省电*：减少动态效果；最后一次更新 10 秒后调暗到最低亮度（任何事件或点击都会恢复）；降低刷新率（更慢的动画节奏，低电量模式也会触发）。

**Mac**（菜单栏图标 → Settings…）：

- *配对*：配对码、“New code”按钮、最近一次配对/拒绝的手机，以及 *Development mode*（无需配对码向任何手机推送）。
- *Agents*：Claude Code、Codex、opencode 和 pi 开关。
- *启动*：登录时启动、启动后隐藏窗口、显示/隐藏菜单栏图标。隐藏菜单栏图标后，从“应用程序”重新打开 Tars 即可找回窗口。

## 构建

Xcode 工程由 [project.yml](../project.yml) 生成；仅在修改它之后才需要运行 `xcodegen generate`。目标：`Tars`（iOS 17+）和 `TarsMac`（macOS 15+）。

```zsh
# iPhone 模拟器，无需签名
xcodebuild -project Tars.xcodeproj -scheme Tars -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/iOS CODE_SIGNING_ALLOWED=NO build

# 使用纯命令行服务端替代菜单栏应用
./Mac/run.zsh                # 开发模式，无需配对
./Mac/run.zsh --code 123456  # 要求此配对码
```

手机应用的 Debug 构建支持 `--preview-state waiting|working|approval|completed` 用于截图；预览模式不会连接服务端。

## 测试

```zsh
/usr/bin/python3 Tests/test_hook.py
/usr/bin/python3 Tests/test_install_hooks.py
xcrun swiftc Mac/Server.swift Mac/EventSource.swift Mac/main.swift -o /tmp/tars-server
python3 Tests/test_server.py /tmp/tars-server
```

服务端测试使用 27893/27894 端口，检查快照、分片输入、优先级、序号、五秒完成保持、重连和输入上限。

## 目录结构

```
iOS/        SwiftUI 手机应用（FaceView、AgentLink、Palette）
MacApp/     SwiftUI 菜单栏应用（设置、钩子安装界面）
Mac/        Server + EventSource（共享）、命令行入口、hook.py、install-hooks.py、
            opencode-plugin.js、pi-extension.ts
Tests/      钩子与安装器单元测试、服务端集成测试
themes/     各主题的参考图片（bit、eva、pika）
doc/        翻译
```

## 已知限制

- 免费 Apple ID 签名 7 天后过期，需从 Xcode 重新安装。
- Bonjour 要求手机和 Mac 在同一网络；它反映的是可达性，而非物理距离。
- 目前只接入了 Claude Code、Codex、opencode 和 pi。其他智能体可以向 17894 端口发送相同的 JSON。
- pi 没有自己的批准事件，因此 pi 会话在等待工具确认时仍显示为工作中。
- 局域网链路未加密，请在可信网络中使用。
