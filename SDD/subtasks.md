# Red Panda Dev-C++ AI Agent 集成：子任务

> 版本：v2.0 | 日期：2026-07-16 | 关联：[design.md](./design.md)

## 文档范围

本文档描述当前实现需要完成和验证的任务。Claude Code CLI 的 transcript 是 AI 上下文的唯一来源；IDE 只保留项目到 Claude 会话的映射，不保存完整聊天副本。

所有涉及 Windows、Delphi 7、Claude CLI 或安装包的验收，都必须在对应环境执行。macOS/Linux 上的静态检查不能替代 Windows 运行验收。

## 不在本期范围内

- 不实现 IDE 自己的完整对话历史 JSON。
- 不调用 cc-switch，不修改用户全局 `~/.claude/settings.json`，不修改系统 `PATH`。
- 不在 `stream-json` stdin 中发送 `yes/no` 作为权限确认。
- 不把原生 OpenAI Chat Completions 地址当作 Claude CLI 地址；非 Anthropic 服务商必须提供兼容 Anthropic API 的端点。
- 不承诺通过 `--continue` 自动恢复任意最近会话，因为这可能恢复到其他项目。项目恢复只使用已保存的 `session_id`。

## Phase 0：运行时与构建前提

### P0.1 准备并锁定 Claude CLI 运行时

**交付物**

- `nodejs/`：发布包根目录下的 Windows portable Node.js。
- `claude-cli/`：发布包根目录下锁定版本的 Claude CLI 及其 `.cmd` 或原生 `.exe` 启动器。
- `AGENT-RUNTIME-VERSIONS.txt`：Node.js 与 Claude CLI 版本记录。

**实现与验证**

1. 在 Windows 构建机使用 Node.js 22 LTS 或更高 LTS 版本；当前锁定的 Claude CLI 要求 Node.js `>=22.0.0`。
2. 使用 npm 安装固定版本的 Claude CLI，例如：

   ```powershell
   npm install -g @anthropic-ai/claude-code@<pinned-version> --prefix .\claude-cli
   ```

3. 直接通过 Windows shell 验证 `.cmd`，不能使用 `node.exe claude.cmd`：

   ```powershell
   .\nodejs\node.exe --version
   cmd /d /c .\claude-cli\bin\claude.cmd --version
   # 如果当前 CLI 包提供原生 launcher，也可直接运行 claude.exe --version
   ```

4. `claude --version` 只能验证本地 CLI 可启动，不能证明 API Key、网络或 Base URL 有效。API 配置验证必须另做一次受控的最小请求测试。
5. 不使用 Linux 的 `curl | bash` 安装脚本作为 Windows 发布验收步骤。

**验收**

- 干净 Windows 机器没有系统 Node.js 时，IDE 能通过 bundled 路径启动 Claude CLI。
- 版本记录与实际输出一致。
- 缺少运行时目录时，IDE 显示可读错误，不崩溃。

### P0.2 Delphi 构建环境检查

**交付物**：构建说明和 CI 检查。

**验收**

- Windows runner 可找到 `dcc32.exe` 和项目依赖。
- CI 缺少 Delphi 编译器时直接失败，不生成占位 exe。
- `git diff --check` 通过。

## Phase 1：基础通路

### P1.1 AgentProcess：进程和管道生命周期

**交付物**：`Source/AgentProcess.pas`。

**实现要求**

1. 使用匿名管道重定向 Claude CLI 的 stdin、stdout 和 stderr；stdout/stderr 合并到同一个读取端。
2. 使用 `CreateProcess` 启动：

   ```text
   claude --print --input-format stream-json --output-format stream-json --verbose
   ```

3. `.cmd/.bat` 必须通过 `COMSPEC /d /s /c` 启动，不能把 `.cmd` 作为 `CreateProcess` 的可执行文件直接传入。
4. 使用 job object 管理 `.cmd -> node -> claude` 进程树。
5. `Stop` 的顺序固定为：标记不再运行、终止 job/进程、等待进程退出、关闭子进程端句柄；读端交给调用方在 Reader 退出后关闭。
6. 不在 UI 回调或 Reader 的 `Synchronize` 回调中 `Sleep`、`WaitFor` 或同步重启。重启由主线程 `TTimer` 调度。
7. `SendMessage` 写入合法 JSONL `user` 事件，并循环处理部分写入。
8. `SendInterrupt` 首选进程组 Ctrl+C，失败时使用确定性的停止路径。
9. `ResumeSessionId` 非空时追加 `--resume <session-id>`。session id 由项目会话文件提供，不能由用户输入直接拼接未经校验的参数。
10. `PermissionMode` 只允许锁定 Claude CLI 支持的值：`manual`、`acceptEdits`、`auto`、`bypassPermissions`、`dontAsk`、`plan`；旧 `default` 配置迁移为 `manual`。

**验收**

- 启动不存在的 CLI 路径返回错误，不泄漏句柄。
- 连续启动/停止 10 次，进程树和句柄均清理。
- 停止时 Reader 的阻塞 `ReadFile` 能返回，关闭 IDE 不死锁。
- `.cmd` 和 `.exe` 两种 CLI 路径都能正确启动。
- resume 命令只包含合法 session id；非法配置回退为新会话启动。

### P1.2 AgentReader：后台读取

**交付物**：`Source/AgentReader.pas`。

**实现要求**

1. `TThread.Execute` 阻塞读取 stdout，按 LF 分割 JSONL，去掉 CR。
2. 在 Reader 线程中只做字节累积和分行；完整行通过 `Synchronize` 回主线程。
3. EOF、管道关闭和读取错误都必须退出循环。
4. 结束时只有在非 `Terminated` 状态才发送一次 `OnProcessExit`。
5. `StopAgent` 先终止子进程，再 `Terminate` Reader，最后 `WaitFor`，确保不会等待一个仍被管道阻塞的线程。
6. 第一版按行同步；只有性能数据证明有必要时，才引入有界批量缓冲。批量缓冲必须定义最大内存和关闭时的 flush 行为。

**验收**

- 分片写入、连续 1000 行、中文 UTF-8 和无尾部 LF 均可正确处理。
- 进程停止后 Reader 在限定时间内退出。
- 主线程回调不访问已释放的 panel 或 process。

### P1.3 AgentProtocol：实际 stream-json 事件解析

**交付物**：`Source/AgentProtocol.pas`。

**实现要求**

解析器必须覆盖真实 CLI 输出，而不是只匹配顶层 `tool_use`：

- `system`，尤其是 `subtype=init`，提取 `session_id`，并保留原始事件供面板显示。
- `assistant.message.content[]` 中的 `text`、`thinking`、`redacted_thinking`、`image`、`document` 和嵌套 `tool_use`，一行可以拆出多个事件。
- `stream_event.event` 的 message/content block 生命周期和 `delta.text` / `delta.thinking` 增量文本。
- `content_block_start.content_block` 中的 `tool_use`。
- `content_block_delta.delta.input_json_delta`：按 block index 累积 partial JSON，在 content block 结束时恢复完整工具参数；不能显示为 AI 文本。
- `user.message.content[]` 中的每一个 `tool_result`，包括 `is_error` 和 `tool_use_id`。
- `result`、`error`、`tool_progress`、`rate_limit_event`、`prompt_suggestion` 和未知事件。

事件结构还要包含 subtype、message id、parent tool id、model、stop reason、usage、费用、耗时、内容块类型、partial/update/protocol-only 标记；完整字段以 `Source/AgentProtocol.pas` 为准：

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

**验收**

- 使用已保存的真实 CLI 样本覆盖 init、assistant 文本、工具开始、工具结果、result、error 和未知事件。
- 非法 JSON、空行和截断 JSON 不抛异常，返回 `aetUnknown` 并保留原文。
- `input_json_delta.partial_json` 不出现在聊天区。
- `stream_event` 的增量文本与完整 assistant/result 不重复显示。
- 一条 assistant 消息中的多个文本块、工具块和多个 tool_result 均不互相覆盖。
- 多个并行工具通过 `tool_use_id` 独立关联，文件刷新不串路径。
- `session_id` 在 system 或 result 事件中均可被提取。

### P1.4 AgentPanel：运行期对话视图

**交付物**：`Source/AgentPanel.pas/.dfm`。

**实现要求**

1. RichEdit 仅展示当前 IDE 运行期的消息，不提供 `LoadHistory/SaveHistory`。
2. `AppendUserMessage`、`AppendAIText`、`AppendSystemMessage` 为当前 UI 的实际公共接口。
3. assistant 增量使用 `SelStart + SelText` 追加；工具调用显示工具名、路径或命令摘要；工具结果显示简短结果。
4. `aetResult` 恢复发送状态；`aetError` 显示错误并进入错误状态；已知 system/hook/扩展状态显示摘要，纯协议 framing 事件不直接刷屏。
5. 发送前附加编译上下文时，明确标记为 IDE 上下文，不改变 Claude 的 session 管理。
6. 输入快捷键、Escape 停止和控件释放期间都不能向已停止的 process 写入。

**验收**

- 流式文本无全量重绘闪烁。
- 发送、停止、空输入、未连接和大文本场景均有稳定状态。
- 切换项目时当前运行期聊天被清空，不显示其他项目的消息。

### P1.5 主窗口集成

**交付物**：`Source/main.pas` 及运行时创建的面板组件。

**实现要求**

- 只在 `Enabled` 且 API Key 已配置时启动 Agent。
- 打开/关闭项目通过 `RestartAgentForCurrentProject` 更新 CWD。
- 关闭 IDE 先停止 Agent，再释放面板依赖。
- 右键操作统一调用已存在的 `TAgentPanelFrame.SendPrompt`，聚焦统一使用 `memoInput`；文档不能引用不存在的 `SendCodeContext`、`ShowAgentPanel` 或 `mmoInput`。

**验收**

- `Ctrl+Alt+A` 切换面板（避开格式化的 `Ctrl+Shift+A`），`Ctrl+L` 聚焦输入框，右键四种代码操作可以发送请求。
- 关闭 IDE 后没有残留 Claude/Node 子进程。

### P1.6 配置与密钥

**交付物**：`Source/AgentConfig.pas`、`Source/AgentSetupFrm.pas/.dfm`。

**实现要求**

- API Key 只在内存中以明文使用，写配置前用 Windows DPAPI 加密。
- Provider、Model、Base URL 和 CLI 路径只作为当前 Agent 子进程的配置。
- 配置对话框提供 Claude CLI 的 `PermissionMode` 选择，不再用三个布尔值声称能表达细粒度权限。
- “验证”至少检查 CLI 可启动；网络/API 验证必须明确是一次真实请求，不能用 `claude --version` 冒充。

**验收**

- 配置文件中不出现明文 API Key。
- DPAPI 解密失败时安全地清空 Key 并提示重新配置。
- 未保存的验证输入不会污染正式配置。

## Phase 2：IDE 联动

### P2.1 编译错误上下文

**交付物**：`Source/main.pas` 的编译结束联动。

**要求与验收**

- 只收集最近一次编译的 error/warning，限制最大长度。
- 发送下一条消息时附加上下文；发送后清除一次性上下文。
- 无错误时不附加空上下文。

### P2.2 工具结果后的编辑器同步

**交付物**：`Source/main.pas` 的 `RefreshAgentFile` 联动。

**实现要求**

1. 识别 Claude 实际工具名的文件修改类（如 `Write`、`Edit`、`MultiEdit`），但以解析出的 `FilePath` 为准，不依赖自造的 `write_file` 名称。
2. 在工具调用结果到达后刷新，不能在工具调用开始时抢先刷新。
3. 只刷新已打开且没有本地未保存修改的编辑器；有未保存修改时跳过并提示，绝不覆盖用户内容。
4. 文件未打开时不强行创建 Tab；磁盘文件仍由 Claude CLI 自己负责写入。
5. 工具没有文件路径时不刷新，避免误刷新当前编辑器。

**验收**

- Write/Edit 成功后，已打开且未修改的 Tab 重新加载并重新解析。
- 已修改 Tab 保留本地内容并显示跳过提示。
- Bash/Read/Glob 等工具不会误触发文件刷新。

### P2.3 CLI 权限模式

**交付物**：`PermissionMode` 配置和 AgentProcess 启动参数。

**实现要求**

- 只传 CLI 原生 `--permission-mode` 值。
- 不弹出一个看似能取消已执行操作的 IDE 权限窗。
- `manual`、`acceptEdits`、`bypassPermissions`、`dontAsk`、`plan`、`auto` 的行为以当前 Claude CLI 版本为准，并在版本升级时重新验收。

**验收**

- 每个模式都能在启动命令中准确出现。
- 旧 `default` 和无效配置被规范化为安全的 `manual`。
- IDE 不向 stdin 发送 `yes/no` 权限文本。

### P2.4 工具调用可视化

**交付物**：`AgentPanel.HandleAgentEvent`。

**实现要求**

- 使用 `if/else` 或专用 `IsFileTool` 函数判断工具名称，避免 Delphi 7 不支持的字符串 `case`。
- `tool_use`、`tool_result` 和 `input_json_delta` 分开渲染。
- 路径和命令按长度截断，避免撑破面板。

**验收**

- 文本、工具、结果和错误事件不会互相串成错误类型。
- 超长工具参数不会导致控件宽度变化或 UI 重绘异常。

### P2.5 项目切换与会话恢复

**交付物**：`Source/main.pas`、`Source/AgentProcess.pas`。

**实现要求**

1. 首次收到 `system.init` 或带 `session_id` 的 `result` 后保存：

   ```text
   <IDE config>\AgentSessions\<project-hash>.session
   ```

2. 文件只包含 session id，不包含聊天内容、API Key 或工具结果。
3. 下次同一项目启动时使用 `--resume <session-id>`。
4. resume 失败时由定时器停止旧进程并新建会话；不能在 Reader 的同步回调中直接 `Stop/WaitFor/Start`。
5. `--continue` 不作为自动跨项目兜底；需要人工恢复时由用户在 Claude CLI 中显式使用。

**验收**

- 同一项目重启后发送的新问题能使用原 Claude session 上下文。
- 不同项目的 session 文件互不相同，切换项目不显示旧项目消息。
- session 文件损坏或会话失效时自动新建会话，不死循环、不阻塞 UI。
- 删除 IDE session 文件不会删除 Claude CLI 自己的 transcript。

### P2.6 输入附件与图片

**交付物**：`Source/AgentPanel.pas/.dfm`、`Source/AgentProcess.pas`、`Source/main.pas`。

**实现要求**

1. 输入区支持文件选择、Windows 文件拖放、附件列表和移除操作。
2. 支持粘贴剪贴板图片；PNG/JPEG/GIF/WebP 和剪贴板图片发送为 Anthropic image content block，并限制单张图片大小。
3. 普通文件只发送路径结构化文本，不把整个文件内容无界复制进 prompt。
4. 附件只存在当前运行期，发送或切换项目后清空，不写入聊天历史。

**验收**

- 单个/多个文件拖到输入区均能显示并在下一条消息中发送。
- 图片文件和剪贴板图片被识别为 image block；无法读取的图片显示可读错误。
- 空文本但有附件时仍可发送；重复附件不会重复加入。

### P2.7 Claude 扩展与完整事件流

**交付物**：`Source/AgentConfig.pas`、`Source/AgentSetupFrm.pas/.dfm`、`Source/AgentProcess.pas`、`Source/AgentPanel.pas`。

**实现要求**

1. 启动 Claude CLI 时追加 `--include-partial-messages`、`--include-hook-events` 和 `--prompt-suggestions`；不启用 `--replay-user-messages`，避免用户消息在面板中重复。
2. 项目级 MCP 配置文件通过 `--mcp-config` 传入，Plugin 目录或 ZIP 通过重复的 `--plugin-dir` 传入；只接受存在且无命令注入字符的路径。
3. system、hook、MCP、Plugin、Skill、进度、限流和建议事件不得静默丢弃；解析出 subtype/摘要并保留原始 JSON。`input_json_delta` 作为协议噪声接收并累积，但不直接显示。
4. 不伪造 `--skill-dir`；明确使用项目 `.claude\\skills` 和 Plugin 内 Skill 的 Claude 原生发现规则。

**验收**

- 扩展配置只影响 Agent 子进程，重启后命令行参数与配置一致。
- hook/system/未知事件在面板可见，解析失败保留原文且不崩溃。
- assistant/result 的重复文本不重复显示，工具进度、限流、建议和 hook 生命周期在面板可见。
- `.claude\\skills`、MCP 配置和 Plugin 在 Windows + 当前锁定 CLI 版本下分别完成真实加载验收。

## Phase 3：发布与质量

### P3.1 Provider 隔离

**交付物**：配置向导、环境块和文档。

**实现要求**

- Provider 切换只影响下一次 Agent 子进程的环境变量和命令行。
- 不执行 `cc-switch use`，不写全局 Claude settings，不影响其他项目、终端或用户正在运行的 Claude CLI。
- DeepSeek 等兼容服务商使用兼容 Anthropic API 的 Base URL，并单独验证。

**验收**

- 两个 IDE 实例或 IDE 与终端同时使用时，切换 Provider 不互相改配置。
- 子进程环境包含预期的 API Key/Base URL，父进程环境不变。

### P3.2 运行时安装包

**交付物**：`devcpp-i686.nsi`、`devcpp-x64.nsi`、release workflow。

**实现要求**

- AI runtime 只包含 Node.js 和 Claude CLI；不打包未使用的 cc-switch。
- 不修改系统 PATH。
- 运行时目录不存在时 NSIS 使用 nonfatal 规则，CI 明确报告缺少发布资产。
- 卸载清理 Node.js 和 Claude CLI 目录。

**验收**

- Full 安装、Minimal 安装和无 AI runtime 的源码包都能正常运行。
- 干净 Windows 安装后 `claude-cli\bin\claude.exe --version`（或 `.cmd` launcher）成功。
- 卸载后不残留打包的 Agent runtime。

### P3.3 快捷键、状态和语言

**交付物**：Agent 面板和语言资源。

**验收**

- Ctrl+L、Ctrl+Alt+A、Escape 和发送键行为与配置一致。
- Ready、Thinking、Executing、Error、Disconnected 状态互斥且可见。
- 中文/英文切换后新增 UI 无未翻译的关键文案。

### P3.4 容错与超时

**交付物**：Reader、main timer 和状态提示。

**实现要求**

- 进程异常退出最多自动重启 3 次，采用主线程 timer 的递增延迟。
- 重启必须重新建立 process、Reader 和 stdout handle 的所有权关系。
- 60 秒超时应由独立 timer 处理；收到首个有效 assistant/tool/result 事件时取消。
- 重启过程中不阻塞 Reader 的 `Synchronize` 回调。

**验收**

- 手动终止 Agent 后能重启。
- 连续失败超过上限后停止重试并提示原因。
- 超时提示不阻塞关闭 IDE，恢复后可发送下一条消息。

### P3.5 性能与静态质量

**验收**

- 普通流式输出下 RichEdit 追加不出现明显卡顿。
- 对高频输出进行基准测试后再决定是否启用 50ms 批量刷新；不能用主观 CPU 百分比作为唯一门槛。
- 所有跨线程共享状态有明确所有权；文件刷新只在主线程执行。
- Delphi 7 编译、Windows 运行和真实 CLI 对话均有记录；无法提供这些环境时必须明确标记为未验收。

## 依赖关系

```text
P0.1 ─┬─ P1.1 ─ P1.2 ─ P1.3 ─ P1.4 ─ P1.5
      └─ P1.6 ────────┘
P1.5 ─┬─ P2.1
      ├─ P2.2
      ├─ P2.3
      ├─ P2.4
      └─ P2.5
P2.1/P2.2/P2.3/P2.5 ─ P3.1/P3.2/P3.3/P3.4/P3.5
```

其中 P2.1、P2.2、P2.3、P2.4 可以并行开发；只有触及同一文件时按代码评审顺序合并，不把整个 Phase 3 错误地串成一条长依赖链。

## 最终验收清单

- [ ] Delphi 7 在 Windows 上完整编译通过。
- [ ] Claude CLI `.cmd` 启动、stream-json 收发和中文流式输出通过。
- [ ] 同一项目 `session_id` 恢复通过；未保存完整聊天 JSON。
- [ ] 不同项目隔离通过；不修改全局 Claude settings 或系统 PATH。
- [ ] 工具结果后的安全文件刷新通过。
- [ ] 权限模式参数与当前 Claude CLI 版本一致。
- [ ] 文件/图片附件、拖放和剪贴板图片通过。
- [ ] MCP 配置、Plugin 目录、项目 `.claude\\skills` 和扩展事件流通过。
- [ ] API Key 配置文件中为 DPAPI 密文。
- [ ] Agent 进程异常退出、重启和 IDE 关闭清理通过。
- [ ] Full/Minimal/绿色包在干净 Windows 上完成安装验收。
