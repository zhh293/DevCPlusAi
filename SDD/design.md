# Red Panda Dev-C++ AI Agent 集成设计

> 版本：v2.0 | 日期：2026-07-16 | 适用版本：Delphi 7 / Windows

## 1. 背景与目标

Red Panda Dev-C++ 需要在 IDE 内提供 AI 编程助手。目标是让用户在编辑器中输入问题、看到 Claude 的流式回答，并让 Agent 以当前项目目录为工作目录执行 CLI 原生支持的工具操作。

本设计的核心约束是：Claude Code CLI 自己维护对话上下文，IDE 不复制一份完整聊天历史。IDE 只保存项目到 Claude `session_id` 的映射，以便进程重启后调用 CLI 的 `--resume`。

## 2. 非目标

- 不实现第二套 AI transcript 或完整聊天 JSON。
- 不使用 cc-switch 或修改用户全局 `~/.claude/settings.json`。
- 不修改系统环境变量和系统 PATH。
- 不通过 stream-json stdin 发送权限确认文本。
- 不承诺自动恢复任意最近会话；`--continue` 由用户在 Claude CLI 中手动使用，IDE 自动恢复只使用明确关联项目的 session id。

## 3. 架构

```text
┌──────────────────────────────────────────────────────────────┐
│ Dev-C++ 主进程                                                │
│                                                              │
│  编辑器/编译器 ──上下文──> AgentPanel                         │
│                              │ SendMessage                    │
│                              ▼                                │
│                       AgentProcess                            │
│                    CreateProcess + pipes                      │
│                              ▲                                │
│                 AgentReader + Synchronize                     │
│                              ▲                                │
│                       AgentProtocol                           │
└──────────────────────────────┼───────────────────────────────┘
                               │ stdin/stdout JSONL
                               ▼
┌──────────────────────────────────────────────────────────────┐
│ Claude Code CLI                                               │
│ --print --input-format stream-json --output-format stream-json│
│ --verbose --include-partial-messages --include-hook-events    │
│ --prompt-suggestions                                          │
│ [--resume] [--mcp-config] [--plugin-dir]                       │
│ CWD = 当前项目目录                                            │
└──────────────────────────────────────────────────────────────┘
```

模块职责：

| 模块 | 职责 |
|---|---|
| `AgentProcess.pas` | 管道、命令行、环境块、job object、session resume、进程停止 |
| `AgentReader.pas` | 阻塞读取 stdout、按 LF 分行、回主线程 |
| `AgentProtocol.pas` | 解析真实 stream-json 事件，拆分内容块，累积工具参数，提取元数据和 session id |
| `AgentPanel.pas` | 当前运行期聊天视图、输入和状态 |
| `AgentConfig.pas` | Provider、Key、Model、Base URL、PermissionMode 等 IDE 配置 |
| `main.pas` | 生命周期、项目切换、session 文件、编辑器同步、重启 timer |

## 4. Claude CLI 会话设计

### 4.1 唯一上下文来源

启动 Claude CLI 后，`system` 的 init 事件通常包含 `session_id`；`result` 事件也可能包含该字段。`AgentProtocol` 将其写入 `TAgentEvent.SessionId`，主窗口收到后保存到：

```text
<IDE config>\AgentSessions\<project-key>_<hash>.session
```

文件内容只有一行 session id。文件名包含可读部分和稳定 hash，避免不同路径或同名项目冲突。

IDE 不保存：

- user/assistant 消息正文；
- tool input/result；
- API Key；
- Claude transcript 的副本。

### 4.2 重启与失效会话

同一项目重新启动 Agent 时，若 session 文件合法，命令行追加：

```text
--resume <session-id>
```

如果进程在还没有发出 `system.init` 前退出，主线程 timer 会停止旧 process 并新建一个不带 `--resume` 的会话。重试逻辑不能从 Reader 的 `Synchronize` 回调直接调用 `WaitFor`，因为 Reader 此时正等待同步回调返回，可能死锁。

`--continue` 不自动使用。它只表示“当前工作目录下最近的 CLI 会话”，不能可靠表达 IDE 项目身份；需要人工恢复时由用户显式执行。

### 4.3 UI 历史的边界

AgentPanel 只显示当前进程生命周期内的消息。项目切换时清空运行期视图；进程意外重启时可保留当前视图作为 UI 展示，但模型上下文以 CLI `--resume` 的结果为准。若恢复失败，面板明确提示已创建新会话。

这避免了“UI 显示旧历史，但模型实际没有这些上下文”的不一致。

## 5. 进程和线程生命周期

### 5.1 启动

1. 计算项目工作目录。
2. 创建 stdout/stderr 合并管道和 stdin 管道。
3. 对父进程保留的句柄清除 `HANDLE_FLAG_INHERIT`。
4. `.cmd/.bat` 通过 `COMSPEC /d /s /c` 启动，`.exe` 直接启动。
5. 创建 job object 并把启动的 shell 进程加入其中。
6. 关闭只供子进程使用的 pipe 端。
7. 启动 `AgentReader`，Reader 接管 stdout 读取期间的生命周期。

### 5.2 停止

停止顺序必须是：

```text
标记 expected stop
    -> 终止 job/进程树
    -> 等待进程句柄退出
    -> Terminate Reader
    -> WaitFor Reader
    -> 关闭 stdout read handle
    -> 释放 process
```

`ReadFile` 可能阻塞，所以必须先让子进程关闭管道。不能在 Reader 的同步回调中执行这套顺序。

### 5.3 异常重启

Reader 发现 EOF/读取错误后只通知主线程。主线程设置状态并启动 `TTimer`，最多重启 3 次；重启过程中重新创建 process、reader 和 handle。重试次数在成功收到有效初始化事件后清零。

## 6. stream-json 协议

CLI 输出是一行一个 JSON 对象，但事件层级并不固定。解析器必须按实际结构处理：

| 事件 | 处理 |
|---|---|
| `system` / `subtype=init` | 提取 session、模型和状态摘要，保留 RawJSON |
| `assistant.message.content[]` | 按 text、thinking、image、document、tool_use 拆分事件 |
| `stream_event` | 解析 message/content block 生命周期和文本增量 |
| `input_json_delta` | 按 block index 累积完整工具参数，不把 partial JSON 当 AI 文本 |
| `user.message.content[].tool_result` | 每个 tool_result 单独生成事件并保留错误标记 |
| `result` | 轮次结束，提取 subtype、stop reason、usage、费用和耗时 |
| `tool_progress` / `rate_limit_event` / `prompt_suggestion` | 映射为进度、限流和建议事件 |
| hook、MCP、Plugin、Skill 状态 | 结构化 subtype/摘要，同时保留 RawJSON |
| 其他/非法 JSON | `aetUnknown`，保留原文 |

`TAgentEvent` 的字段以 `Source/AgentProtocol.pas` 为准：

```pascal
TAgentEvent = record
  EventType: TAgentEventType;
  TopLevelType, Subtype, SessionId, EventId, MessageId: String;
  ParentToolUseId, Model, ContentType, BlockIndex: String;
  Content, Summary, ToolName, ToolId, ToolInput: String;
  FilePath, Command, StopReason, Usage, PermissionDenials: String;
  CostUSD, DurationMs: String;
  RawJSON: String;
  IsError, IsPartial, IsUpdate, IsProtocolOnly, IsReplay: Boolean;
end;
```

`ParseLineEvents` 是主入口，因为一条 `assistant` JSON 可能同时含有文本和多个工具块；`ParseLine` 仅作为兼容旧调用的首事件接口。启用 `--include-partial-messages` 时，面板会将流式增量与完整 assistant/result 文本去重；工具参数增量按 block index 累积到 `content_block_stop` 再关联文件路径和命令。解析失败不能让 Reader 线程或主线程异常退出。

## 7. 输入、权限与 Provider 隔离

### 7.1 输入

面板发送的文本被封装为 JSONL `user` 事件，写入 Claude CLI stdin。IDE 上下文作为文本的一部分附加，并明确标记为 IDE 生成的上下文。

输入区还维护一个待发送附件列表：

- 文件可以通过选择按钮或 Windows 文件拖放加入列表；普通文件只发送路径和读取提示，不把整个文件复制进 prompt。
- PNG、JPEG、GIF、WebP 以及剪贴板图片会转为 Anthropic 兼容的 base64 image content block。
- 发送前可以移除任意附件；发送成功后清空附件列表。附件不进入 IDE 的历史存储。

### 7.4 Claude 扩展

Claude CLI 本身负责加载项目和用户范围的 Skill、Plugin、MCP 以及 hook。IDE 不实现一套平行扩展运行时：

- 启动参数固定包含 `--include-partial-messages` 和 `--include-hook-events`，未知输出保留 `RawJSON`，system/扩展状态不再静默丢弃。
- `McpConfigFiles` 以分号分隔的文件路径传给 `--mcp-config`；`PluginDirs` 以分号分隔的目录或 ZIP 传给重复的 `--plugin-dir`。
- Skill 没有对应的 `--skill-dir` 参数，项目 Skill 放在工作目录的 `.claude\\skills`，插件内 Skill 随 Plugin 加载；设置界面对此明确提示。
- 扩展配置只作用于当前 Agent 子进程，不修改全局 Claude settings。

### 7.2 权限

Claude CLI 的权限模型是 CLI 级别的 `--permission-mode`，不能用三个独立布尔值精确表达“读允许、写询问、执行拒绝”。因此配置使用单一 `PermissionMode`，取值限制为当前 CLI 支持的模式：

```text
manual | acceptEdits | auto | bypassPermissions | dontAsk | plan
```

IDE 不弹出一个发生在 tool event 之后的假确认框，也不向 JSONL 输入通道发送 `yes/no`。真实权限行为由 CLI 在工具执行前决定。

### 7.3 Provider

Provider 配置只进入 Agent 子进程的自定义环境块，例如：

- `PATH`：将 bundled Node.js、Claude CLI 和编译器路径置于子进程 PATH 前部；
- `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN`：按兼容网关需要设置；
- `ANTHROPIC_BASE_URL`：非默认端点设置。

父进程和其他终端不看到这些覆盖值。切换 Provider 的正确动作是停止当前 Agent、更新配置、启动新的子进程；不调用 cc-switch，也不修改全局 Claude settings。

原生 OpenAI Chat Completions 地址不能直接传给 Claude CLI。DeepSeek 等服务商必须提供兼容 Anthropic API 的 endpoint，并单独做真实请求验收。

## 8. IDE 联动

### 8.1 编译错误

编译结束后，主窗口从错误列表收集有界的 error/warning 文本。发送下一条消息时追加一次性上下文，发送后清除。编译列表为空时不追加空段落。

### 8.2 文件同步

工具事件只作为“正在执行”的展示；文件刷新触发在工具结果到达之后。解析器从工具 input 提取 `FilePath`，不假设工具名是自造的 `write_file`。

刷新条件：

1. 有明确文件路径；
2. 文件存在；
3. 文件已在 IDE 中打开；
4. 编辑器没有未保存的本地修改。

不满足条件时跳过并提示，绝不覆盖未保存内容，不因 Bash/Read/Glob 误刷新当前 Tab。

### 8.3 右键代码操作

主窗口运行时创建四个 Action，通过实际存在的 `TAgentPanelFrame.SendPrompt` 发送选中代码。聚焦使用实际的 `memoInput` 控件。文档和实现不定义不存在的 `SendCodeContext`、`ShowAgentPanel` 或 `mmoInput` 接口。

## 9. 配置与安全

`TdevAgentConfig` 使用项目现有的 `SettoDefaults / LoadSettings / SaveSettings` 模式。配置项包括：

```text
Enabled / Provider / ApiKey / Model / BaseUrl / CliPath
PanelPosition / PanelWidth / FontSize / SendKey
PermissionMode / McpConfigFiles / PluginDirs
SystemPrompt
```

API Key 写入配置前使用 Windows DPAPI；进程环境块只在创建子进程时构造，不调用 `SetEnvironmentVariable` 修改 IDE 环境。旧版三个 `AutoAllow*` 字段只用于兼容读取，新的 PermissionMode 是唯一生效配置。

## 10. 发布结构

```text
DevCPlusAi/
├── devcpp.exe
├── MinGW64/ 或 MinGW32/
├── nodejs/                 # Windows portable Node.js
├── claude-cli/             # 锁定版本的 Claude CLI
├── Lang/ Templates/ Help/
└── README.md
```

安装脚本不写系统 PATH。AI runtime 是可选安装项；如果没有 bundled runtime，用户仍可在设置中指定外部 Claude CLI。发布包不包含未使用的 cc-switch。

## 11. 风险和处理

| 风险 | 处理 |
|---|---|
| CLI stream-json 结构变化 | 锁定版本、保存真实样本、解析未知事件为 RawJSON |
| session id 失效 | timer 调度新会话，避免同步回调死锁 |
| CLI/Node 子进程残留 | job object + 先停进程再等 Reader |
| 未保存编辑器内容被覆盖 | 仅刷新未修改 Tab，修改 Tab 跳过 |
| Provider 污染其他终端 | 只传递自定义 CreateProcess 环境块 |
| API Key 泄漏 | DPAPI 存储，文档和日志不打印 Key |
| 高频输出卡顿 | 先按行验证，基准测试证明必要时再启用有界批量 flush |
| 缺少 Delphi/Windows 环境 | 静态检查可以通过，但发布验收必须标记为未完成 |

## 12. 验收标准

- Delphi 7 在 Windows 上编译通过。
- Claude CLI stream-json 输入输出可以实际收发中文消息。
- 首次启动捕获并保存项目 `session_id`，重启使用 `--resume`。
- UI 不保存完整聊天 JSON，且不会显示与模型上下文不一致的伪历史。
- 项目切换、工具结果后的文件刷新、编译上下文和右键操作通过。
- PermissionMode 参数与当前 Claude CLI 版本一致，不发送假权限确认。
- Provider 切换不调用 cc-switch、不修改全局 settings、不污染父进程环境。
- API Key 使用 DPAPI；Full/Minimal 安装和卸载完成 Windows 验收。
