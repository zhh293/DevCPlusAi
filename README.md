# DevCPlusAi

DevCPlusAi 是一款**集成了 AI 编程助手的 C/C++ 集成开发环境（IDE）**。它在经典的小熊猫 Dev-C++ 编辑器内核之上，把一个 AI Agent（基于 Claude Code CLI）直接嵌入到 IDE 中，让你在写代码的同时就能与 AI 对话、答疑、生成与修改代码，无需离开编辑器、也无需在浏览器和 IDE 之间来回切换。

项目面向 C/C++ 初学者与教学场景，目标是把「智能编程辅助」做成一种开箱即用、贴近母语（中文）交互的体验。

---

## 核心亮点

DevCPlusAi 在保留一个轻量、纯 Windows 原生 C/C++ IDE 的基础上，新增了一整套 AI 辅助能力。

* **IDE 内置 AI 对话面板。** AI 助手以一个可停靠的侧边面板形式驻留在主窗口中（默认停靠在右侧），包含聊天显示区、多行输入框、发送/停止按钮以及状态栏。你可以一边看代码一边提问，对话不会打断你的编辑流程。

* **流式实时响应。** AI 的回答采用 stream-json 协议逐行解析、实时呈现，而不是等全部生成完才一次性显示，交互体验更流畅。

* **AI 进程由 IDE 统一托管。** AI 后端以子进程方式运行，其启动、停止、重启与中断（Ctrl-C 风格的中断信号）全部由 IDE 管理，进程生命周期与编辑器窗口保持一致，关闭 IDE 时自动清理，不留残余进程。

* **首次启动配置向导。** 第一次使用时会自动弹出向导，引导你填写服务商、API Key、自定义端点（Base URL）和模型，并可现场验证 CLI 是否可启动。配置完成后随 IDE 设置一起持久化，下次启动直接可用。

* **丰富的可配置项。** 支持服务商与模型选择、自定义端点、面板停靠位置与宽度、字体大小、发送快捷键（回车发送 / Shift+回车换行），以及对读 / 写 / 执行类操作的 CLI 权限模式控制。

* **项目级会话恢复。** Claude CLI 自己保存对话上下文，IDE 只按项目保存 `session_id`，重新打开项目时通过 `--resume` 恢复；CLI 意外退出时最多自动重启 3 次。

* **附件与扩展能力。** 输入区支持选择文件、从 Windows 资源管理器拖放文件、粘贴剪贴板图片和发送 PNG/JPEG/GIF/WebP 图片内容；普通文件以路径附件交给 Claude 的文件工具读取。剪贴板图片使用唯一临时文件名，发送、移除、切换项目或关闭 IDE 时自动清理；用户手动选择的原文件不会被删除。设置中可填写项目级 MCP 配置文件和 Plugin 目录，CLI 输出中的 system、hook、MCP、Plugin、Skill 相关事件会保留在面板中。

* **稳定的英文 AI 界面。** AI 配置向导、面板与提示使用英文 ASCII，避免 Delphi 7 在不同系统代码页下出现乱码；对话内容仍可使用中文。

---

## 工作原理

DevCPlusAi 把 AI 能力拆分为几个职责单一、相互解耦的 Object Pascal 单元，整体数据流如下：

```
  用户输入 ──► AgentPanel ──► AgentProcess ──(stdin)──► Claude CLI 子进程
                                                              │
                                                          (stdout)
                                                              ▼
  对话面板 ◄── AgentPanel ◄── AgentProtocol ◄── AgentReader（后台读取线程）
```

IDE 启动 AI 子进程时使用的命令形如：

```
"<CliPath>" --print --input-format stream-json --output-format stream-json --verbose --include-partial-messages --include-hook-events --prompt-suggestions [--append-system-prompt-file "<temporary-utf8-file>"]
```

子进程以独立进程组（`CREATE_NEW_PROCESS_GROUP`）创建，便于精确地向子进程单独投递中断信号；环境变量块沿用 Delphi 7 工程的 ANSI 表示。`AgentReader` 在后台线程中按行读取子进程标准输出，交由 `AgentProtocol` 解析成结构化事件后，再通过线程安全的方式回调到 UI 面板上渲染。

用户消息通过 stdin 发送为 Claude CLI 的 JSONL `user` 事件。没有附件时 content 是普通文本；有图片时使用 Anthropic 兼容的 image content block，普通文件使用带路径的 text block。输出仍按 stdout 的 `stream-json` 事件逐行渲染，未知事件保留原始 JSON。非 Anthropic 服务商需要填写兼容 Anthropic API 的 Base URL；原生 OpenAI API 地址不能直接作为 Claude CLI 端点使用。

---

## 项目结构

AI 集成相关的核心源码位于 `Source/` 目录：

| 文件 | 职责 |
|------|------|
| `Source/AgentProcess.pas` | AI CLI 子进程生命周期管理：启动 / 停止 / 重启、消息收发、中断信号、环境变量块构造 |
| `Source/AgentReader.pas` | 继承自 `TThread` 的后台读取线程，逐行读取子进程标准输出并通过 `Synchronize` 安全回调 |
| `Source/AgentProtocol.pas` | stream-json 协议解析：一行可拆分多个内容块事件，累积流式工具参数，保留元数据和原始 JSON |
| `Source/AgentPanel.pas` / `.dfm` | 对话面板 UI：聊天显示区、输入框、发送/停止按钮、状态栏 |
| `Source/AgentConfig.pas` | AI 助手配置类 `TdevAgentConfig`，基于 RTTI 的「默认值 / 读取 / 保存」三段式配置持久化 |
| `Source/AgentSetupFrm.pas` / `.dfm` | 首次启动配置向导窗体 |
| `Source/main.pas` | 主窗口集成：运行时挂载对话面板与分隔条、注册菜单项、触发首启向导 |

其余目录为 Dev-C++ 编辑器内核及其配套资源；`SDD/` 目录存放本项目的需求与设计文档。

---

## DeepSeek V4

在 AI Settings 中选择 DeepSeek，模型默认是 `deepseek-v4-flash`，也可选择 `deepseek-v4-pro` 或输入网关模型 ID。填写自己的 DeepSeek API Key；Base URL 为 `https://api.deepseek.com/anthropic`。Validate 只检查 CLI 启动，真实联网需发送一条消息确认。

旧 DeepSeek 配置中的空模型、`deepseek-chat` 和 `deepseek-reasoner` 会迁移到 V4 Flash。显式选择的 Pro 和自定义模型不会被覆盖。官方根地址及 `/v1` 会转换为 Anthropic 兼容地址，自定义网关地址保留。

V4 的 CLI 参数带 `[1m]` 上下文标记；主模型、默认角色模型和子任务模型都映射到所选 DeepSeek 模型。这些设置只写入 IDE 启动的子进程环境，不改全局 Claude 配置或系统环境。

AI 面板沿用 IDE 字体与编辑器主题颜色，支持亮色和暗色切换。顶部 Settings 直接打开配置；底部 Send/Stop 共用紧凑位置，附件列表仅在有附件时显示。回归测试覆盖模型迁移、子进程环境隔离、原生窗体加载、窄宽布局和主题颜色。真实 API 对话仍需使用有效凭据验收。

面板顶部选择 Explain code、Fix code、Improve code、Add comments 或 Diagnose build errors，再点 Run。优先使用编辑器选区，没有选区则使用当前文件；普通聊天也会附带当前编辑内容（包括未保存内容，最多 24,000 字节）和最近的编译错误。Copy answer 复制当前回答，Open code 将回答的第一个完整 Markdown 代码块打开为新编辑标签页，便于检查、修改和编译。Logs 控制后续诊断日志显示，API 重试和错误仍会显示；思考块不再混入正文。

输入框和回答区支持 Ctrl+C、Ctrl+V、Ctrl+A，以及右键菜单；输入框还支持剪切、撤销和 Shift+Insert 粘贴。在回答区粘贴会把文字放进输入框。流式回复到来时会保留已选中的文字，便于复制。工具调用在发生时插入对话流，每个调用独立折叠；结果更新原位置，前后文字顺序不变。点击工具标题展开参数与结果，支持复制；历史恢复保留这些块的顺序。

点击 New chat 新建会话，通过旁边的历史下拉框选择旧会话继续。每个工作目录分别保存会话 ID、正文、工具记录和输入草稿；关闭程序后会恢复最后选中的会话。历史记录存放在本机配置目录的 AgentSessions/History 下，不进入发布包。旧版本在当前工作目录留下的 Claude CLI 历史也会进入列表，首次选择时导入正文；恢复上下文仍需要对应 CLI 会话文件存在。新会话不会继承旧会话 ID。

Windows 构建中的 AgentMainSmoke 使用本地模拟 CLI 检查真实的 `--resume` 参数、会话切换和重启恢复，不使用 API Key 或网络；AgentUISmoke 覆盖工具折叠、正文隔离、历史快照与输入草稿。

接口参考：[DeepSeek Claude Code 接入](https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code/)。

## 配置项说明

AI 助手的全部配置由 `TdevAgentConfig` 统一管理，主要包括：

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `Enabled` | 是否启用 AI 助手 | `True` |
| `Provider` | 服务商 | `anthropic` |
| `ApiKey` | API 密钥（首启向导中填写，掩码显示） | 空 |
| `Model` | 使用的模型 | 空（由向导/服务商决定） |
| `BaseUrl` | 自定义端点 | 空 |
| `CliPath` | AI CLI 可执行文件路径；可在英文设置窗口中修改 | `<程序目录>\claude-cli\bin\claude.exe` |
| `PanelPosition` | 兼容配置字段；当前版本固定右侧停靠，无效值会归一化为 `right` | `right` |
| `PanelWidth` | 面板宽度（像素） | `400` |
| `FontSize` | 面板字体大小，可在英文设置窗口中设为 8–24 | `10` |
| `SendKey` | 发送快捷键，可在英文设置窗口中选择 Enter 或 Ctrl+Enter | `enter` |
| `PermissionMode` | Claude CLI 原生权限模式 | `manual` |
| `McpConfigFiles` | 传给 `--mcp-config` 的配置文件路径，多个路径用 `;` 分隔 | 空 |
| `PluginDirs` | 传给 `--plugin-dir` 的目录或 ZIP 路径，多个路径用 `;` 分隔 | 空 |
| `SystemPrompt` | 追加系统提示词；以无 BOM UTF-8 临时文件传给 CLI，并在子进程结束后删除 | 空 |

配置随 IDE 设置一并保存，下次启动自动加载。项目会话目录只保存 Claude 的 `session_id`，不保存完整聊天内容；API Key 写入配置前会通过 Windows DPAPI 加密。消息只有在完整写入 CLI 的 JSONL 输入管道后才会显示为已发送；写入失败会立即显示英文错误并重启异常子进程。每次成功发送后由独立主线程定时器等待首个有效 assistant/tool/result 事件；60 秒内无响应时会中断本次请求并显示英文错误提示。

---

## 构建与运行

DevCPlusAi 是一个 **Windows + Delphi / Object Pascal** 工程，需要在 Windows 平台上使用 Delphi / RAD Studio 编译。

1. 在 Delphi / RAD Studio 中打开 `Source/devcpp.dpr`。
2. 编译生成可执行文件。
3. 发布包会内置 portable Node.js 和锁定版本的 AI CLI（默认路径为程序目录下的 `claude-cli\bin\claude.exe`，也兼容 `claude.cmd`）；开发环境也可以在配置向导中指定外部 CLI。
4. 首次运行 IDE 时会弹出配置向导，填写服务商、API Key、Base URL 与模型后即可开始使用 AI 对话面板。后续可通过 `工具 → AI Settings...` 修改配置。使用 `视图 → AI Assistant` 或 `Ctrl+Alt+A` 切换 AI 面板，`Ctrl+L` 聚焦输入框；`Ctrl+Shift+A` 保留给原有代码格式化功能。

API Key 只在进程内以明文使用，写入 IDE 配置时会通过 Windows DPAPI 加密；旧版本留下的明文配置会兼容读取，并在下次保存时迁移为密文。发布包必须包含 `nodejs`、`claude-cli` 和 `AGENT-RUNTIME-VERSIONS.txt`，不能只发布主程序。Provider 配置只注入 Agent 子进程，不调用 cc-switch，也不修改全局 Claude settings。

### 准备发布包运行时

发布仓库通过 `runtime-packages/` 保存版本锁定的 Windows 压缩包。发布构建机可以直接执行：

```powershell
.\tools\prepare-agent-runtime.ps1 `
  -NodeArchive .\path\to\node-vXX.YY.ZZ-win-x64.zip `
  -ClaudeCliSource .\path\to\claude-cli `
  -NodeVersion XX.YY.ZZ `
  -ClaudeCliVersion X.Y.Z
```

也可以把 `-ClaudeCliSource` 换成已经解压好的 CLI 目录。脚本会验证 `node.exe` 和 `claude.exe/claude.cmd --version`，生成 `AGENT-RUNTIME-VERSIONS.txt`。NSIS 和 Release workflow 会把运行时作为必需资源；缺少运行时会直接失败，不会生成一个表面可安装但无法使用 Agent 的包。正式分发前还需要确认 Node.js 和 Claude CLI 的再分发许可。

## 本地构建完整安装包

完整安装包需要在 **Windows** 上完成。macOS/Linux 可以阅读和修改源码，但不能替代 Delphi、NSIS 和 Windows CLI 的真实验证。当前仓库提供的是 Windows x64 运行时，因此建议先构建 `devcpp-x64.nsi`。

### 1. 准备工具

需要安装并加入当前命令行 `PATH`：

- Delphi 7 或兼容本工程的 Delphi 编译器，能够运行 `dcc32.exe`；
- NSIS，能够运行 `makensis.exe`；
- Git；
- Windows x64 环境。

安装包还要求以下文件或目录存在于仓库根目录：

```text
devcpp.exe
packman.exe
PackMaker.exe
ConsolePauser.exe
MinGW64/
Lang/ Templates/ Help/ Icons/
AStyle/ ResEd/ contributes/
nodejs/ claude-cli/ AGENT-RUNTIME-VERSIONS.txt
```

### 2. 解压 Agent 运行时

仓库中的两个压缩包是远端构建和本地构建的输入。打开 `cmd.exe` 或 PowerShell，在仓库根目录执行：

```powershell
.\tools\prepare-agent-runtime.ps1 `
  -NodeArchive .\runtime-packages\node-v24.18.0-win-x64.zip `
  -ClaudeCliArchive .\runtime-packages\claude-code-2.1.211-win-x64.zip `
  -NodeVersion 24.18.0 `
  -ClaudeCliVersion 2.1.211
```

确认启动器存在：

```powershell
.\nodejs\node.exe --version
.\claude-cli\bin\claude.exe --version
```

两条命令都成功后再继续。这个步骤不修改系统 PATH，也不需要在用户电脑上执行 `npm install`。

### 3. 编译 Dev-C++ 主程序

在仓库根目录打开 Delphi 命令行：

```bat
cd Source
dcc32.exe -B devcpp.dpr -E. -N.\dcu
cd ..
copy /Y Source\devcpp.exe devcpp.exe
```

也可以在仓库根目录执行一键构建脚本。它会编译资源、主程序、Packman、
PackMaker 和 ConsolePauser，并把发布所需的四个 EXE 复制到仓库根目录：

```bat
tools\build-windows.cmd
```

如果 Delphi 的完整 `Lib` 不在默认安装目录，可通过
`-DelphiLibPath <目录>` 指定包含 `Spin.dcu` 的目录。
精简安装的 Delphi 7 可能只有 `Spin.dcu` 而缺少配套的 `SPIN.RES`；构建脚本
会从仓库内的兼容位图资源自动生成该文件。仓库不分发 Delphi 自带的 DCU，
因此全新构建环境仍需安装完整 Delphi 7 库，或显式指定合法的 `Spin.dcu` 来源。

构建后可检查无编译器安装包所需资源及锁定的 Agent 运行时版本：

```bat
tools\verify-release.cmd -PackageType NoCompiler
```

生成包含 Agent 运行时的免安装 ZIP：

```bat
tools\package-portable.cmd -Version dev
```

如果构建机已安装带 `7z.sfx` 的 7-Zip，也可以同时生成单文件自解压免安装版：

```bat
tools\package-self-extracting.cmd -Version dev
```

双击生成的 `DevCPlusAi-<版本>-windows-no-compiler-self-extracting.exe` 后选择目录即可解压运行，不需要管理员权限。它是便携分发形式，不会创建开始菜单快捷方式或卸载项；需要这些系统集成功能时仍应使用 NSIS 安装包。构建脚本会附带并校验 `7-ZIP-LICENSE.txt`，同时对 SFX 内全部文件执行完整性测试。

上述两个便携产物都是**无编译器版**：AI 助手和编辑器可以直接运行，但编译 C/C++ 前仍需另行安装并在 IDE 中配置兼容的 GCC/MinGW 工具链。本地 `dev` 构建没有商业代码签名证书，Windows 可能显示 SmartScreen 提示；正式公开分发应使用可信证书签名，并同时发布脚本输出的 SHA-256。不要为了运行未签名构建而全局关闭 Windows 安全功能。

脚本会核对关键文件的 SHA-256；如果本机装有 7-Zip，还会对 ZIP 中的全部
条目执行 CRC 完整性测试。包内的 `BUILD-INFO.txt` 会记录源码提交、工作区
状态、运行时版本以及四个可执行文件的 SHA-256。

一键脚本会同时生成 NSIS 依赖的 `Packman.exe`、`PackMaker.exe` 和
`ConsolePauser.exe`；后者使用当前 `PATH` 中的 `g++.exe` 静态编译。

### 4. 构建安装器

确认第 1 步列出的文件全部存在后，在仓库根目录执行：

```bat
makensis.exe devcpp-x64.nsi
```

成功后会在仓库根目录生成类似以下文件：

```text
Dev-Cpp.6.7.5.MinGW-w64 X86_64 GCC 10.3 .Setup.exe
```

NSIS 对 `nodejs/`、`claude-cli/` 和 `AGENT-RUNTIME-VERSIONS.txt` 使用必需文件规则。缺少运行时会直接失败，不能通过跳过文件生成不完整安装包。

### 5. 安装后验收

在干净的 Windows 目录安装后，先检查：

```bat
<安装目录>\nodejs\node.exe --version
<安装目录>\claude-cli\bin\claude.exe --version
```

然后启动 Dev-C++，在 AI 设置中填写 API Key、Provider、Model 和兼容 Anthropic API 的 Base URL，发送一条最小问题。最后再验证项目切换、session 恢复、文件修改刷新以及关闭 IDE 后没有残留 `claude.exe` 进程。

### 常见失败原因

- `dcc32.exe` 找不到：使用 Delphi 命令行，或把 Delphi 的 `Bin` 目录加入 PATH。
- NSIS 找不到 `devcpp.exe`：先把 `Source\devcpp.exe` 复制到仓库根目录。
- NSIS 找不到 Agent runtime：重新执行第 2 步，不要手动创建空目录。
- Claude CLI 无法启动：确认使用 Windows x64，并先单独运行 `claude.exe --version`。
- CLI 可以启动但对话失败：检查 API Key、网络、Provider 和 Anthropic-compatible Base URL；这不是安装问题。

当前 `devcpp-i686.nsi` 不应直接复用 x64 runtime。若要发布 i686 版本，需要单独准备与目标系统兼容的 Node.js 和 Claude CLI 运行时。

> 说明：本仓库基于小熊猫 Dev-C++（Red Panda Dev-C++）的编辑器内核进行二次开发，在其之上新增了完整的 AI Agent 集成能力。

---

## 开发状态

基础对话通路和 IDE 联动已经接入：编译错误上下文、已打开文件刷新、项目切换重启、CLI 权限模式、编辑器选中代码快捷提问、项目级 session 恢复、进程自动重启与 60 秒首响应超时、文件/图片附件、追加系统提示词、MCP 配置和 Plugin 目录参数均已接入。Skill 不使用不存在的 `--skill-dir` 参数，Claude CLI 会按当前项目工作目录自动发现 `.claude\skills` 和插件内 Skill。本地 Windows + Delphi 7 全量编译及协议、Reader 管道分片/UTF-8/1000 行、输入管道完整写入/断管失败、CLI 参数、ConsolePauser 冒烟测试已通过；三种 NSIS 脚本的 Agent runtime 安装/卸载约束已纳入静态发布校验。新增的 `AgentUISmoke` 会实际加载 AI 面板和设置窗体，并检查三种宽度下的按钮布局及 Send/Stop 状态；原有 `btnAttach.Align` 故障已验证会使测试以非零状态退出。仍需完成真实 API 对话和完整安装包 GUI 验收。GitHub Actions 在缺少 `dcc32.exe` 时会直接失败，不再生成占位 exe。

普通权限模式通过 CLI 的 stdio 审批通道弹出工具审批窗口，显示工具、工作目录与完整参数。Allow once 只允许本次，Deny 或关闭窗口拒绝；不会自动修改权限模式。
