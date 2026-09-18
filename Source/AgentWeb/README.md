# AI chat renderer

`AgentPanel` loads `AgentWeb/index.html` through the x86 `AgentWebHost.dll` bridge. Keep the DLL and the complete `AgentWeb` folder beside `devcpp.exe`. Microsoft Edge WebView2 Runtime must be installed. Missing assets, initialization timeout and browser process failure expose a retry button in the native panel.

## Build and deployment

Run `tools/build-windows.ps1 -SkipConsolePauser` for the application and integration checks. `tools/deploy-agent-web.ps1` builds the bridge and copies the web assets. The native build uses MSVC x86 and Microsoft.Web.WebView2 SDK 1.0.4191.47 at `.tools/webview-sdk/extracted`.

## Data and lifetime

`AgentPanelWeb.inc` queues browser commands and dispatches them from the VCL timer. Modal dialogs never open inside a WebView COM callback. Message IDs combine conversation generation and block index. Timeline revisions avoid serializing unchanged conversations. Changed messages retain chronological position, tool expansion, code controls and reading offsets. Updates intersecting selected text wait until the selection is released.

Delphi owns the WebView parent. The bridge synchronizes controller visibility and bounds with that window. Closing a view suppresses asynchronous callbacks into Delphi. The DLL remains loaded until process exit because queued COM callbacks can retain its code pointers.

Tool input, output and status are stored with the timeline. Permission requests appear inline at their chronological position. File approvals show the resolved target path, working directory scope and a code preview; command approvals show the exact command. AskUserQuestion renders single-choice, multi-choice and custom-answer controls and returns a validated `answers` object through the CLI permission response. The IDE checks the active request ID before sending a decision, marks unanswered requests expired when the process ends, and loads historical approvals as non-actionable. The renderer cannot directly execute tools. Session removal hides the conversation with a `.deleted` marker while retaining its local records; the history scanner excludes those records from automatic import.

## Protocol

All packets contain `version: 1`. Host packets use `PostWebMessageAsJson`; browser packets are JSON strings.

Host packets:

- `state`: busy/status, model, theme, permission mode, session list, selected session, attachments and send shortcut.
- `upsert`: item with stable `id`, immutable `kind`, cumulative `text`, and optional tool `name`, `status`, `input`, `output`.
- `reset`: changes the conversation and clears pending message updates.
- `draft`: restores the input draft.
- `accepted` / `rejected`: acknowledges `requestId`. Acceptance clears only the submitted draft, preserving edits typed while sending.

Browser actions: `draft`, `send`, `stop`, `session`, `new`, `rename-session`, `delete-session`, `settings`, `attach`, `paste-image`, `remove`, `copy`, `open-code`, `open-code-block`, `context`, `clear`, `logs`, `quick`, and `permission` (`requestId`, `decision`, and optional serialized `answers`).

## Rendering and tests

Marked 17.0.5 supplies Markdown tokens. Rendering creates fixed DOM nodes with text content; model output never becomes arbitrary HTML or JavaScript. Raw HTML is displayed as text. Links and images are represented as text, and message content cannot initiate network requests. The bundled Marked license is in `vendor/marked.LICENSE.md`.

- `tools/verify-agent-web-messages.cjs` checks Markdown, code actions, input transactions, IME handling, selection retention, scroll behavior, structured tools, history actions, safe rendering and responsive layouts.
- `Source/Tests/AgentWebPanelSmoke.dpr` checks native startup, visibility transitions, host dispatch, Unicode drafts, tool persistence, resizing and teardown.
- `Source/Tests/AgentWebControlSmoke.dpr` checks parent guard, bridge roundtrip and destruction during asynchronous initialization.
- `Source/Tests/AgentMainSmoke.dpr` checks approval decisions, clipboard routing, session persistence, history removal and project isolation.

Native IME behavior and visual acceptance on other DPI settings require testing on the target desktop.
