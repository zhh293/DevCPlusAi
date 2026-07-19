# Red Panda Dev-C++ AI Agent 集成需求文档

> 版本: v1.0  
> 作者: zhanghonghao  
> 日期: 2025-06  
> 状态: 草案（实现约束以 [design.md](./design.md) v2.0 为准）

> 当前决策覆盖：Claude CLI transcript 是 AI 上下文的唯一来源。IDE 只保存项目对应的 `session_id` 并用 `--resume` 恢复，不保存完整聊天 JSON；Provider 通过子进程环境块隔离，不使用 cc-switch 或修改全局 Claude settings。

---

## 一、产品定位与目标

### 1.1 产品定位

在 Red Panda Dev-C++ 6.7.5 基础上集成 AI Agent 能力，使其成为面向 C/C++ 零基础学生的 **AI 辅助编程环境**。底层不自研 Agent，而是通过进程管道直接桥接 Claude Code CLI（及其他兼容 Agent CLI），以最小改动量获得顶级 Agent 的完整能力。

### 1.2 核心目标

- **开箱即用**：学生下载安装包后，无需额外配置即可获得「编辑器 + 编译器 + AI Agent」一体化环境
- **零学习成本**：对话式交互，学生无需知道 CLI、终端、API Key 等概念
- **顶级 Agent 能力**：底层调用 Claude Code / 其他 Coding Agent，具备文件读写、编译执行、错误分析、代码生成的完整能力
- **可切换后端**：通过当前 Agent 子进程的环境块切换 Anthropic-compatible Provider；不影响其他项目、终端或全局 Claude 配置

### 1.3 目标用户

大一新生，使用 Windows 系统，正在学习 C/C++ 语言课程，此前从未接触过编程工具。

---

## 二、系统架构

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────┐
│                  Red Panda Dev-C++ GUI                   │
│                                                         │
│  ┌──────────────────────┐  ┌─────────────────────────┐  │
│  │   代码编辑区域        │  │    AI Agent 对话面板     │  │
│  │   (SynEdit 编辑器)    │  │                         │  │
│  │                      │  │  ┌───────────────────┐  │  │
│  │   - 语法高亮         │  │  │  对话历史显示区    │  │  │
│  │   - 代码补全         │  │  │  (RichEdit/HTML)   │  │  │
│  │   - 行号/折叠        │  │  │                   │  │  │
│  │                      │  │  └───────────────────┘  │  │
│  │                      │  │  ┌───────────────────┐  │  │
│  │                      │  │  │  用户输入框        │  │  │
│  │                      │  │  │  (Memo + Send Btn) │  │  │
│  │                      │  │  └───────────────────┘  │  │
│  └──────────────────────┘  └─────────────────────────┘  │
│                                                         │
│  ┌────────────────────────────────────────────────────┐  │
│  │         编译输出 / 终端面板 (现有)                  │  │
│  └────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                          │
                 CreateProcess + Pipe
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│              Claude Code CLI 子进程                       │
│                                                         │
│  - 工作目录 = 当前项目文件夹                             │
│  - stdin  ← 用户输入（经 GUI 转发）                     │
│  - stdout → AI 输出（流式渲染到对话面板）                │
│  - 自动感知工作目录下所有源文件                           │
│  - 可执行 gcc 编译、运行程序、读写文件                    │
│                                                         │
│  [兼容端点] 可切换到支持 Anthropic API 的服务商           │
└─────────────────────────────────────────────────────────┘
```

### 2.2 技术选型依据

| 组件 | 选型 | 理由 |
|------|------|------|
| AI Agent 后端 | Claude Code CLI | 当前最强 Coding Agent 之一，开箱支持文件操作/编译/调试 |
| 进程通信方式 | CreateProcess + Anonymous Pipe | 项目已有成熟实现（Tabnine.pas, DebugReader.pas），零风险复用 |
| 模型切换 | Agent 子进程环境块 | 不修改系统 PATH 或全局 Claude 配置 |
| UI 面板 | Delphi VCL TPanel + TRichEdit | 与现有 IDE 风格一致，无需引入新 UI 框架 |
| 安装打包 | NSIS 脚本（现有） | 扩展现有 .nsi 脚本，追加 Claude Code 安装步骤 |

---

## 三、安装流程设计

### 3.1 安装包组成

```
RedPandaDevCpp-AI-Setup.exe
├── MinGW-w64 GCC 编译器（现有）
├── Red Panda Dev-C++ 主程序（含 AI 面板）
├── Node.js 运行时（LTS，portable 版本，Claude Code 依赖）
├── Claude Code CLI（通过 npm 全局安装）
└── 首次启动配置向导
```

### 3.2 安装步骤（用户视角）

#### 步骤 1：运行安装程序

用户双击 `RedPandaDevCpp-AI-Setup.exe`，看到标准安装向导界面。

#### 步骤 2：选择安装路径

默认路径：`C:\RedPandaDevCpp\`（避免 Program Files 权限问题）

安装目录结构：
```
C:\RedPandaDevCpp\
├── devcpp.exe              # IDE 主程序
├── MinGW64\               # GCC 编译器
├── nodejs\                # Node.js portable 运行时
├── claude-cli\            # Claude Code CLI
├── Lang\                  # 语言文件
└── Templates\             # 项目模板
```

配置位置沿用 IDE 现有的 `devDirs.Config` 机制，不在本需求中强制改为程序目录；绿色版只有在单独验证可写目录策略后才能发布。

#### 步骤 3：AI 配置向导（首次启动时弹出）

安装完成后首次启动 IDE，弹出 AI 配置向导对话框：

```
┌─────────────────────────────────────────────┐
│         🤖 AI 助手配置                       │
│                                             │
│  欢迎使用 AI 编程助手！                      │
│  请选择你的 AI 服务提供商：                   │
│                                             │
│  ○ Anthropic (Claude) [推荐]                │
│  ○ OpenAI (GPT)                             │
│  ○ Google (Gemini)                          │
│  ○ DeepSeek                                 │
│  ○ 其他 (OpenAI 兼容接口)                   │
│                                             │
│  API Key: [________________________]        │
│                                             │
│  [如何获取 API Key？]  [跳过，稍后配置]      │
│                                             │
│           [确定]     [取消]                  │
└─────────────────────────────────────────────┘
```

#### 步骤 4：配置验证

用户填写 API Key 后，程序自动执行验证：
- 调用 `claude --version` 确认 CLI 可用
- 发送一条测试请求确认 API Key 有效
- 验证通过后显示「✓ AI 助手已就绪」

#### 步骤 5：安装完成

显示安装摘要：
- ✓ C/C++ 编译器已就绪 (GCC x.x.x)
- ✓ AI 编程助手已就绪 (Claude Code vx.x.x)
- ✓ 可选：桌面快捷方式 / 文件关联

### 3.3 安装流程（技术实现）

#### 3.3.1 NSIS 脚本扩展

安装器不在用户电脑上联网执行 `npm install`。发布构建机先准备并锁定
portable Node.js 和 Claude CLI，运行 `tools/prepare-agent-runtime.ps1` 进行
版本和启动校验，并生成 `AGENT-RUNTIME-VERSIONS.txt`。现有 NSIS 脚本随后把
以下目录作为必需文件复制到安装目录：

```text
$INSTDIR\nodejs\*
$INSTDIR\claude-cli\*
$INSTDIR\AGENT-RUNTIME-VERSIONS.txt
```

缺少上述运行时资产时，NSIS 和 Release workflow 直接失败，不生成缺少 AI
运行时的伪完整安装包。这样用户安装过程不依赖 npm、代理、网络或本机 Node.js
版本；正式发布前仍需确认 Node.js 与 Claude CLI 的再分发许可。

#### 3.3.2 环境变量隔离

安装时不污染系统全局 PATH。IDE 启动时通过 `CreateProcess` 的 `lpEnvironment` 参数注入自定义 PATH：

```pascal
// 伪代码
EnvBlock := GetEnvironmentStrings + 
            'PATH=' + InstallDir + '\nodejs;' + 
            InstallDir + '\claude-cli\bin;' + 
            InstallDir + '\MinGW64\bin;' + 
            OriginalPATH;
```

---

## 四、AI 对话面板 UI 设计

### 4.1 面板位置与布局

AI 对话面板作为 IDE 右侧的可停靠面板（Dockable Panel），类似现有的 Class Browser 面板。

#### 默认布局

```
┌────────────────────────────────────────────────────────────┐
│ 菜单栏 | 工具栏                                            │
├──────────────────────────────────┬─────────────────────────┤
│                                  │  🤖 AI 助手             │
│                                  │  ─────────────────────  │
│       代码编辑区域                │  [对话历史区]           │
│                                  │                         │
│                                  │  User: 帮我写一个       │
│                                  │  冒泡排序               │
│                                  │                         │
│                                  │  AI: 好的，我来帮你     │
│                                  │  实现冒泡排序...        │
│                                  │  ```c                   │
│                                  │  void bubble_sort(...)  │
│                                  │  ```                    │
│                                  │  我已将代码写入         │
│                                  │  sort.c 文件            │
│                                  │                         │
│                                  ├─────────────────────────┤
│                                  │ [输入框                 │
│                                  │          ] [发送] [⚙️]  │
├──────────────────────────────────┴─────────────────────────┤
│ 编译输出 / 调试信息 面板                                    │
└────────────────────────────────────────────────────────────┘
```

#### 面板可切换位置
- 右侧停靠（默认）
- 底部停靠
- 浮动窗口
- 隐藏（通过菜单 View → AI Assistant 切换）

### 4.2 对话面板组件

#### 4.2.1 对话历史显示区

- **组件类型**：TRichEdit 或 自定义 HTML 渲染控件
- **功能需求**：
  - 区分显示用户消息（右对齐/蓝色气泡）和 AI 回复（左对齐/灰色气泡）
  - 代码块语法高亮显示（至少支持 C/C++ 高亮）
  - 流式输出：AI 回复时逐字/逐行追加显示，不等待完整回复
  - 显示 Agent 操作状态：「正在读取 main.c...」「正在编译...」「正在执行...」
  - 支持滚动浏览当前运行期消息；不由 IDE 保存完整 transcript
  - 右键菜单：复制、全选、清空对话

#### 4.2.2 用户输入框

- **组件类型**：TMemo（多行输入）
- **功能需求**：
  - 支持多行输入（Shift+Enter 换行，Enter 发送）
  - 支持选择文件、拖拽一个或多个文件到输入区、移除待发送附件
  - 支持 PNG/JPEG/GIF/WebP 文件和剪贴板图片；图片以 image content block 发送
  - 普通文件以路径附件发送，由 Claude 文件工具读取
  - 输入框高度可自适应（1-5 行）
  - 发送按钮 + 快捷键 (Enter / Ctrl+Enter 可配置)

#### 4.2.3 工具栏

- **⚙️ 设置按钮**：打开 AI 配置对话框（切换模型、修改 API Key）
- **🗑️ 清空按钮**：清空当前运行期视图；是否创建新 Claude session 由明确的重启操作决定
- **📋 上下文按钮**：手动添加当前文件/选中代码到上下文
- **⏹️ 停止按钮**：中断当前 AI 回复（发送 SIGINT 到子进程）
- **📎 附件按钮**：选择文件、粘贴图片、查看和移除待发送附件

### 4.3 交互流程

#### 4.3.1 普通对话

```
用户输入 → GUI 将文本写入 claude 进程 stdin → 
claude 处理 → stdout 流式输出 → GUI 实时渲染到对话面板
```

#### 4.3.2 Agent 操作权限

文件写入和命令执行由 Claude CLI 的 `--permission-mode` 原生策略控制。IDE 展示 tool/hook/system 输出，但不在操作发生后伪造一个无法撤销的确认框，也不向 stdin 发送 `yes/no`。

#### 4.3.3 快捷操作

在编辑器右键菜单中添加 AI 相关选项：
- **「Ask AI: 解释这段代码」** — 将选中代码发送给 AI 并附带"请解释"指令
- **「Ask AI: 修复错误」** — 将选中代码 + 最近编译错误发送给 AI
- **「Ask AI: 优化代码」** — 将选中代码发送给 AI 并附带"请优化"指令
- **「Ask AI: 添加注释」** — 将选中代码发送给 AI 并附带"请添加注释"指令

### 4.4 状态指示

对话面板顶部显示 Agent 状态：
- 🟢 **就绪** — Agent 空闲，可接受输入
- 🔵 **思考中...** — Agent 正在处理请求
- 🟡 **等待确认** — Agent 需要用户确认操作
- 🔴 **未连接** — Agent 进程未启动或 API Key 无效
- ⚙️ **执行中** — Agent 正在执行编译/运行等操作

---

## 五、Agent 进程管理

### 5.1 生命周期

```
IDE 启动 → 打开项目/文件 → 启动 Agent 子进程（CWD = 项目目录）
                              │
                              ▼
                    Agent 进程运行中 ←──── 用户对话
                              │
                              ▼ (用户关闭项目/切换项目)
                    终止旧 Agent → 启动新 Agent（新 CWD）
                              │
                              ▼ (用户关闭 IDE)
                    终止 Agent 子进程 → IDE 退出
```

### 5.2 进程启动（参考 Tabnine.pas 实现）

```pascal
// AgentProcess.pas - 核心进程管理类
TAgentProcess = class(TObject)
private
  fOutputRead: THandle;    // 读取 Agent stdout
  fInputWrite: THandle;    // 写入 Agent stdin
  fProcessID: THandle;     // Agent 进程句柄
  fReaderThread: TAgentReaderThread;  // 异步读取线程
  fWorkDir: String;        // 工作目录
  fExecuting: Boolean;
public
  procedure Start(const WorkDir: String);
  procedure Stop;
  procedure SendMessage(const UserInput: String);
  property OnOutput: TAgentOutputEvent;       // 收到输出回调
  property OnStatusChange: TStatusChangeEvent; // 状态变更回调
end;

procedure TAgentProcess.Start(const WorkDir: String);
begin
  // 1. 构建命令行
  //    claude --output-format stream-json
  //    (使用 JSON 流式输出，便于解析操作类型)
  
  // 2. CreateProcess，CWD 设为项目目录
  //    参考 Tabnine.pas 第 153-225 行的管道创建逻辑
  
  // 3. 启动 ReaderThread 异步读取 stdout
end;
```

### 5.3 输入输出协议

#### 输入（GUI → Agent stdin）

将用户输入封装为 Claude CLI 的 JSONL `user` 事件后写入 stdin：
```
{"type":"user","message":{"role":"user","content":"用户消息"}}\n
```

#### 输出（Agent stdout → GUI）

使用 Claude Code 的 `--output-format stream-json` 模式，每行一个 JSON 事件：
```json
{"type":"system","subtype":"init","session_id":"..."}
{"type":"assistant","message":{"content":[{"type":"text","text":"好的，我来帮你写一个冒泡排序..."}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"...","name":"Write","input":{"file_path":"sort.c","content":"..."}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"...","content":"文件已写入"}]}}
{"type":"result","session_id":"...","result":"任务完成"}
```

GUI 解析 JSON 事件并分类渲染：
- `assistant` → 渲染为 AI 消息气泡
- `tool_use` → 渲染为操作卡片（显示文件名、操作类型）
- `tool_result` → 渲染为操作结果

### 5.4 异步读取线程

```pascal
// 参考 DebugReader.pas 的 TThread 实现
TAgentReaderThread = class(TThread)
private
  fPipeRead: THandle;
  fCurrentLine: AnsiString;
  procedure ProcessLine;  // Synchronize 回调，更新 UI
protected
  procedure Execute; override;
end;

procedure TAgentReaderThread.Execute;
var
  bytesRead: DWORD;
  buffer: array[0..4095] of AnsiChar;
  lineBuffer: AnsiString;
begin
  while not Terminated do begin
    if ReadFile(fPipeRead, buffer, SizeOf(buffer), bytesRead, nil) then begin
      // 按行分割，每完成一行就 Synchronize 更新 UI
      // 参考 devrun.pas 的 RunAndGetOutput 逻辑
    end else
      break;
  end;
end;
```

---

## 六、配置管理

### 6.1 配置文件

位置：`<InstallDir>\config\ai-config.ini`

```ini
[Agent]
; AI 提供商: anthropic / openai / gemini / deepseek / custom
Provider=anthropic

; API Key (加密存储)
ApiKey=sk-ant-xxxxx

; 模型名称
Model=claude-sonnet-4-20250514

; Claude Code CLI 路径
CliPath=C:\RedPandaDevCpp\claude-cli\bin\claude.cmd

[UI]
; 面板位置: right / bottom / float
PanelPosition=right

; 面板宽度 (像素)
PanelWidth=400

; 字体大小
FontSize=12

; 发送快捷键: enter / ctrl+enter
SendKey=enter

[Permissions]
; Claude CLI 原生权限模式
PermissionMode=manual

[Extensions]
; 可选 MCP 配置文件，多个路径用分号分隔
McpConfigFiles=
; 可选 Plugin 目录或 ZIP，多个路径用分号分隔
PluginDirs=

[Advanced]
; 输出格式：stream-json
OutputFormat=stream-json

; 自定义系统提示词（追加到 Agent 默认提示词后）
SystemPrompt=你是一位耐心的 C 语言教学助手。请用中文回答，解释要简单易懂，适合零基础学生。
```

### 6.2 AI 设置对话框

通过菜单 `Tools → AI Settings...` 或对话面板的 ⚙️ 按钮打开：

```
┌────────────────────────────────────────────────────┐
│                 AI 助手设置                          │
├────────────────────────────────────────────────────┤
│                                                    │
│  [基本设置] [权限控制] [高级选项]                    │
│                                                    │
│  ─── 基本设置 ───                                  │
│                                                    │
│  AI 提供商:  [Anthropic (Claude)    ▼]             │
│  API Key:    [sk-ant-*************    ] [验证]     │
│  模型:       [claude-sonnet-4-20250514        ▼]             │
│                                                    │
│  ─── 界面设置 ───                                  │
│                                                    │
│  面板位置:   ○ 右侧  ○ 底部  ○ 浮动               │
│  字体大小:   [12 ▼]                                │
│  发送方式:   ○ Enter 发送  ○ Ctrl+Enter 发送       │
│                                                    │
│  ─── 教学配置 ───                                  │
│                                                    │
│  系统提示词: [你是一位耐心的C语言教学助手...]       │
│  □ 回答时优先解释原理而非直接给答案                 │
│  □ 自动在代码中添加中文注释                         │
│                                                    │
│              [确定]  [取消]  [恢复默认]             │
└────────────────────────────────────────────────────┘
```

### 6.3 模型切换实现

Provider 切换只作用于下一次 Agent 子进程，通过 `CreateProcess` 的自定义环境块注入兼容 Anthropic API 所需的 Key 和 Base URL。

#### GUI 封装为下拉选择

```pascal
procedure SwitchProvider(Provider: String; ApiKey: String);
begin
  // 通过 CreateProcess 的 lpEnvironment 注入：
  //   ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN / ANTHROPIC_BASE_URL
  
  // 重启 Agent 子进程使配置生效
  AgentProcess.Stop;
  AgentProcess.Start(CurrentWorkDir);
end;
```

#### 支持的切换方式

| 方式 | 适用场景 | 实现 |
|------|----------|------|
| 项目级 Provider | IDE 内切换 | 停止旧进程后为新进程构建环境块 |
| 外部 CLI 配置 | 用户手动管理 | IDE 只使用用户指定的 CLI 路径，不覆盖其全局设置 |

---

## 七、核心使用场景

### 7.1 场景一：新手写第一个程序

**用户操作**：
1. 打开 IDE，新建一个空文件 `hello.c`
2. 在 AI 面板输入：「帮我写一个 Hello World 程序」

**Agent 行为**：
1. 感知到当前打开的文件是 `hello.c`
2. 生成代码并请求写入文件
3. GUI 弹出确认：「AI 想要写入 hello.c，是否允许？」
4. 用户点击「允许」
5. 代码自动出现在编辑器中
6. AI 回复：「我已经帮你写好了 Hello World 程序。按 F9 可以编译运行看效果。」

### 7.2 场景二：编译报错求助

**用户操作**：
1. 编写了一段有语法错误的代码
2. 按 F9 编译，底部面板显示编译错误
3. 在 AI 面板输入：「编译报错了，帮我看看」

**Agent 行为**：
1. 自动读取当前文件内容和编译错误输出
2. 分析错误原因
3. 回复解释 + 修复方案
4. 请求修改文件中的错误行
5. 用户确认后，代码被修复
6. AI 建议：「已修复，你可以再按 F9 试试。」

### 7.3 场景三：逐步学习指导

**用户操作**：
1. 输入：「我想学习怎么用指针，能给我讲讲吗？」

**Agent 行为**：
1. 给出简单易懂的指针概念解释
2. 提供一个循序渐进的示例代码
3. 建议用户尝试运行并修改
4. 根据用户后续问题进一步深入

### 7.4 场景四：右键快捷操作

**用户操作**：
1. 选中编辑器中一段代码
2. 右键 → 「Ask AI: 解释这段代码」

**Agent 行为**：
1. GUI 自动将选中代码作为上下文发送给 Agent
2. Agent 逐行解释代码含义
3. 回复显示在 AI 面板中

---

## 八、与现有功能的集成点

### 8.1 编译错误联动

当编译产生错误时，自动将错误信息注入 Agent 上下文（不自动发送，而是在用户下次提问时附带）：

```pascal
procedure TMainForm.OnCompileError(ErrorList: TStringList);
begin
  // 将编译错误暂存，下次 Agent 对话时自动附带
  AgentPanel.SetCompileContext(ErrorList.Text);
  // 在 AI 面板显示提示：「检测到编译错误，可以问我如何修复」
  AgentPanel.ShowHint('检测到 ' + IntToStr(ErrorList.Count) + ' 个编译错误，可以问我如何修复');
end;
```

### 8.2 文件变更同步

Agent 修改文件后，IDE 需要感知并刷新编辑器：

```pascal
procedure TAgentProcess.OnFileModified(const FilePath: String);
begin
  // 查找该文件是否已在编辑器中打开
  Editor := EditorList.FindByFilePath(FilePath);
  if Editor <> nil then begin
    // 重新加载文件内容
    Editor.ReloadFromDisk;
    // 高亮变更行（可选）
    Editor.HighlightChangedLines;
  end else begin
    // 文件未打开，更新文件树即可
    FileTreeView.Refresh;
  end;
end;
```

### 8.3 项目感知

Agent 进程的工作目录始终与 IDE 当前项目/文件夹保持同步：

- 打开 `.dev` 项目文件 → CWD = 项目所在目录
- 打开单独的 `.c` 文件 → CWD = 文件所在目录
- 切换项目 → 终止旧 Agent 进程，以新 CWD 重启

---

## 九、权限与安全

### 9.1 操作权限分级

| 操作类型 | 风险等级 | 默认行为 | 可配置 |
|----------|----------|----------|--------|
| 读取文件 | 低 | 自动允许 | ✓ |
| 写入/创建文件 | 中 | 弹窗确认 | ✓ |
| 执行编译命令 | 中 | 弹窗确认 | ✓ |
| 执行任意命令 | 高 | 弹窗确认 | ✓ |
| 删除文件 | 高 | 弹窗确认（不可自动允许） | ✗ |
| 网络访问 | 高 | 弹窗确认 | ✓ |

### 9.2 沙箱约束

- Agent 的工作目录严格限制在当前项目文件夹内
- 禁止访问项目目录之外的文件系统（除编译器目录）
- 禁止执行与项目无关的系统命令
- 所有文件修改操作均可通过 IDE 内置的撤销功能恢复

### 9.3 API Key 安全

- API Key 使用 Windows DPAPI 加密存储在用户 AppData 目录
- 不以明文形式写入配置文件
- 卸载时提示用户是否清除凭据数据

---

## 十、安装包结构

### 10.1 完整安装包（推荐）

```
RedPandaDevCpp-AI-7.0-x64-Full.exe
├── Dev-C++ 主程序
├── MinGW-w64 GCC 13.x
├── Claude Code CLI (Node.js runtime 内嵌)
├── ConsolePauser.exe
└── 默认配置与模板
```

预计安装包大小：~250MB（含编译器和 Node.js runtime）

### 10.2 精简安装包

```
RedPandaDevCpp-AI-7.0-x64-Lite.exe
├── Dev-C++ 主程序
├── MinGW-w64 GCC 13.x
├── ConsolePauser.exe
└── 默认配置与模板
```

精简版不含 bundled AI runtime；不会自动在线安装。用户可以在设置中指定已安装的 Claude CLI。

### 10.3 NSIS 安装脚本修改

基于现有 `devcpp-x64.nsi` 扩展：
- 新增 AI Agent 运行时文件组，包含 Node.js 和 Claude Code CLI
- 发布构建前校验运行时版本和 `claude.exe --version`（兼容 `.cmd` launcher）
- 安装过程只复制已校验的本地文件，不在线安装 npm 包
- 不注册系统 PATH；由 AgentProcess 为子进程构建隔离环境块

---

## 十一、技术实现要点

### 11.1 进程管理（参考 Tabnine.pas）

```pascal
// 核心实现模式 - 与 Tabnine.pas 完全一致
TAgentProcess = class(TObject)
private
  fOutputRead: THandle;   // 读取 claude stdout
  fInputWrite: THandle;   // 写入 claude stdin
  fProcessID: THandle;
  fReaderThread: TAgentReaderThread;  // 后台读取线程
public
  procedure Start(const WorkDir: string);  // 启动 claude 进程
  procedure Stop;                           // 终止进程
  procedure SendMessage(const Msg: string); // 发送用户输入
end;
```

### 11.2 输出解析

Claude Code CLI 支持 `--output-format stream-json` 模式，每行输出一个 JSON 对象：

```json
{"type":"system","subtype":"init","session_id":"..."}
{"type":"assistant","message":{"content":[{"type":"text","text":"这是回复内容"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"main.c","content":"..."}}]}}
{"type":"result","session_id":"...","result":"任务完成"}
```

解析逻辑：
- `system` / hook / MCP / Plugin / Skill 状态 → 提取 subtype 和摘要，同时保留原始 JSON
- `assistant.message.content[]` → 按文本、思考、图片、文档和工具块拆分
- `stream_event` → 解析文本增量、工具输入增量和消息生命周期
- `input_json_delta` → 按 block index 累积，不直接显示 partial JSON
- `user.message.content[].tool_result` → 每个结果独立展示并关联 `tool_use_id`
- `result` → 提取成功/失败、usage、费用、耗时并结束本轮
- `tool_progress` / `rate_limit_event` / `prompt_suggestion` → 显示进度、限流和建议
- 未知或非法事件 → 保留原始内容，不让读取线程退出

启动参数还包含 `--include-partial-messages` 和 `--include-hook-events`。由于 Claude 可能同时输出流式增量和完整 assistant/result，面板按 message id 和文本前缀去重。项目 Skill 按 Claude CLI 原生规则放在工作目录的 `.claude\\skills`，不伪造不存在的 `--skill-dir` 参数。

### 11.3 UI 面板实现

新增 Delphi 窗体单元：
- `AgentFrm.pas` / `AgentFrm.dfm` — Agent 对话面板
- `AgentProcess.pas` — 进程生命周期管理
- `AgentReader.pas` — stdout 读取线程（参考 DebugReader.pas）
- `AgentConfig.pas` — 配置管理（API Key、模型选择）
- `AgentSetupFrm.pas` / `AgentSetupFrm.dfm` — 首次配置向导

### 11.4 与现有模块的集成点

| 集成点 | 现有模块 | 集成方式 |
|--------|----------|----------|
| 编译错误传递 | Compiler.pas → OnOutput 事件 | Agent 监听编译事件，自动获取错误信息 |
| 当前编辑器内容 | Editor.pas → TEditor | Agent 通过 claude 读取工作目录文件 |
| 调试信息 | DebugReader.pas | Agent 可读取 watch/backtrace 信息 |
| 文件变更通知 | devFileMonitor | 文件被 Agent 修改后刷新编辑器内容 |
| 项目文件列表 | Project.pas → TProject | 提供工作区上下文 |

---

## 十二、多语言支持

在 `Lang/Chinese.lng` 和 `Lang/English.lng` 中新增以下条目：

```ini
[AI Agent]
AgentPanel=AI 助手
AgentInput=在此输入问题...
AgentSend=发送
AgentStop=停止
AgentClear=清除对话
AgentSetup=配置 AI
AgentNotReady=AI 助手未配置，点击此处开始设置
AgentThinking=正在思考...
AgentReadingFile=正在读取 %s
AgentWritingFile=正在修改 %s
AgentCompiling=正在编译...
AgentPermissionMode=CLI 权限模式
```

---

## 十三、发布计划

### Phase 1：基础对话（2周）
- Agent 面板 UI
- 进程管理（启动/停止/重启）
- 基础文本对话（stdin/stdout pipe）
- 配置向导（API Key 设置）

### Phase 2：IDE 集成（2周）
- 编译错误自动传递给 Agent
- 文件变更后自动刷新编辑器
- CLI 原生 PermissionMode
- 操作卡片可视化（显示文件修改 diff）

### Phase 3：体验优化（1周）
- 快捷键支持
- 右键菜单集成
- 项目 session_id 保存与 `--resume` 恢复（不保存完整聊天 JSON）
- 多模型切换 UI

### Phase 4：打包发布（1周）
- NSIS 安装脚本修改
- 内嵌 Claude Code CLI + Node.js runtime
- 完整安装包测试
- 编写用户文档

---

## 十四、成功指标

| 指标 | 目标值 |
|------|--------|
| 安装到首次 AI 对话时间 | < 5 分钟 |
| 安装包体积（完整版） | < 300 MB |
| AI 首次响应延迟 | < 3 秒 |
| 内存占用增量 | < 100 MB |
| 编译错误解释准确率 | > 90% |
| 目标用户（大一新生）可独立完成安装比例 | > 95% |

---

## 十五、风险与应对

| 风险 | 影响 | 应对措施 |
|------|------|----------|
| Claude Code CLI 更新导致接口不兼容 | Agent 功能失效 | 锁定 CLI 版本，安装包内嵌固定版本 |
| Provider 兼容端点不可用 | 请求失败 | 在配置向导中要求 Anthropic-compatible Base URL，并使用真实请求验证 |
| API Key 费用对学生不友好 | 用户流失 | 支持多模型切换，接入免费/低价模型 |
| 网络环境不稳定（校园网） | 响应慢或超时 | 增加超时重试机制，离线时优雅降级 |
| Delphi 编译环境难以获取 | 无法编译项目 | 文档中提供 Delphi 7/2007 社区版获取方式 |
| 学校机房可能禁止安装软件 | 无法使用 | 提供绿色免安装版（解压即用） |

---

## 附录 A：Claude Code CLI 常用参数

```bash
# 基础对话模式（交互式）
claude --output-format stream-json

# 指定工作目录
claude --cwd /path/to/project --output-format stream-json

# 项目会话恢复：由 IDE 保存并校验 session id 后追加
claude --resume <session-id> --print --input-format stream-json \
  --output-format stream-json --verbose

# 非交互式单次查询
claude -p "解释这段代码" --output-format json

# 带权限控制
claude --allowedTools "read,write,compile" --output-format stream-json
```

## 附录 B：现有代码参考映射

| 新增模块 | 参考现有模块 | 复用点 |
|----------|--------------|--------|
| AgentProcess.pas | Tabnine.pas | CreateProcess + Pipe 通信模式 |
| AgentReader.pas | DebugReader.pas | TThread 后台读取 + Synchronize 回调 |
| AgentFrm.pas | CPUFrm.pas | 可停靠面板 UI 布局 |
| AgentConfig.pas | devCFG.pas | INI 配置读写模式 |
| 编译集成 | Compiler.pas | OnOutput 事件监听模式 |
