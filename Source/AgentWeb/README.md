# AI chat renderer

`AgentPanel` loads `AgentWeb/index.html` through the x86 `AgentWebHost.dll` bridge. Keep the DLL and the complete `AgentWeb` folder beside `devcpp.exe`. Microsoft Edge WebView2 Runtime must be installed. Missing assets, initialization timeout and browser process failure expose a retry button in the native panel.

## Build and deployment

Run `tools/build-windows.ps1 -SkipConsolePauser` for the application and integration checks. `tools/deploy-agent-web.ps1` builds the bridge and copies the web assets. The native build uses MSVC x86 and Microsoft.Web.WebView2 SDK 1.0.4191.47 at `.tools/webview-sdk/extracted`.

## Data and lifetime

`AgentPanelWeb.inc` queues browser commands and dispatches them from the VCL timer. Modal dialogs never open inside a WebView COM callback. Message IDs combine conversation generation and block index. Timeline revisions avoid serializing unchanged conversations. Changed messages retain chronological position, tool expansion, code controls and reading offsets. Updates intersecting selected text wait until the selection is released.

Delphi owns the WebView parent. The bridge synchronizes controller visibility and bounds with that window. Closing a view suppresses asynchronous callbacks into Delphi. The DLL remains loaded until process exit because queued COM callbacks can retain its code pointers.

Tool input, output and status are stored with the timeline. Common built-in tool names are localized in Chinese while unknown and MCP-provided names remain intact. The composer keeps six one-click code actions visible after the first message; on narrow panels the action rail scrolls horizontally. The empty state and action menu offer the same learning walkthrough, which explains code flow, traces a small example, covers complexity and edge cases, and ends with a self-check without editing files. Each user message carries a short `contextSummary` showing which IDE file, selection or caret, unsaved state, and compiler diagnostics were attached to that request. When source context was sent, its exact text is also stored in local conversation history and shown in a collapsed disclosure under that message, so students can review the evidence behind an answer later. The composer shows the last synchronized context and offers a one-click refresh. Expanding its summary reveals the exact IDE text appended to the request (including the safety preamble) and its character count; the snapshot used for a running request stays available for review. Every send refreshes the IDE context automatically. Permission requests appear inline at their chronological position. File approvals show the resolved target path, working directory scope and a code preview; likely mojibake in proposed file text produces a non-blocking warning before approval. Command approvals show the exact command. AskUserQuestion renders single-choice, multi-choice and custom-answer controls and returns a validated `answers` object through the CLI permission response. The IDE checks the active request ID before sending a decision, marks unanswered requests expired when the process ends, and loads historical approvals as non-actionable. The renderer cannot directly execute tools. Session removal hides the conversation with a `.deleted` marker while retaining its local records; the history scanner excludes those records from automatic import.
History removal uses an expiring two-step confirmation. Pressing Escape, clicking outside the history panel, or waiting five seconds cancels it.

The composer’s “附加 IDE 上下文” checkbox defaults on and controls whether the live editor snapshot and compiler diagnostics are sent with each message. The preference is stored in the existing Agent configuration and survives app restarts. Its summary remains visible when context is off, with a tooltip explaining that it is only a preview. User messages record when IDE context was intentionally omitted; messages with attached context retain that source text in local conversation files for later review.

The composer exposes a responsive quick picker for Plan, Manual approval and Accept Edits. It is disabled while a request or permission is active. Changing the mode persists the preference and restarts the CLI, attempting to resume the active session. The result packet confirms success or returns the previous mode and a visible error; advanced permission modes remain available in Settings.

Selecting text in an assistant response reveals “追问这段”. It adds a quoted follow-up to the existing draft without sending it; code selections retain their detected language fence.

The native manual-approval window shows a color-coded unified diff for `Write` and `Edit` requests, including the current file, proposed result, and added/removed line counts. It only reads existing targets inside the active working directory, and caps the file at 2 MB and the line comparison at four million cells. Outside-workspace targets are never opened automatically. If the file cannot be decoded or the change is too large to compare responsively, the dialog explains why and falls back to the complete request details. The in-chat undo action is disabled while any assistant request or approval is active; the host checks the same condition before restoring a file.

When a conversation contains file edits, the header shows a unique-file count. Its review list groups repeated edits by path, summarizes available diff counts, and expands and scrolls to the latest matching timeline card. Clearing or switching conversations resets this overview; each card remains the source of truth for its own diff, open-file action and guarded undo.

## Protocol

All packets contain `version: 1`. Host packets use `PostWebMessageAsJson`; browser packets are JSON strings.

Host packets:

- `state`: busy/status, model, theme, permission mode, session list, selected session, attachments (current hosts send `{name,path}` objects; the renderer still accepts legacy filenames), `contextEnabled`, last synchronized `contextSummary` and exact `contextPayload`, send shortcut and chat font name/size.
- `upsert`: item with stable `id`, immutable `kind`, cumulative `text`, optional user `contextSummary` and `contextPayload`, and optional tool `name`, `status`, `input`, `output`.
- `reset`: changes the conversation and clears pending message updates.
- `draft`: restores the input draft.
- `accepted` / `rejected`: acknowledges `requestId`. Acceptance clears only the submitted draft, preserving edits typed while sending.

Browser actions: `draft`, `send`, `stop`, `session`, `new`, `rename-session`, `delete-session`, `settings`, `permission-mode`, `attach`, `paste-image`, `remove`, `copy`, `copy-code-block`, `open-code`, `open-code-block`, `insert-code-block`, `open-file`, `open-link`, `context`, `context-enabled`, `clear`, `logs`, `quick`, and `permission` (`requestId`, `decision`, and optional serialized `answers`). The composer `context` action refreshes the active file, selection/caret and compiler diagnostics; `context-enabled` controls whether that IDE data is attached to outgoing messages. Assistant Markdown links to absolute HTTP(S) URLs open in the default browser only after a click; credentials and other schemes are rejected in both the renderer and native host. Each assistant message has a copy action that preserves its complete Markdown source. Assistant answers, code blocks and file diffs fall back to the IDE clipboard when browser clipboard access is denied, then select their content and explain Ctrl+C if both routes fail. Code-block insertion is disabled while a response is still streaming. Once complete, it shows the destination file before replacing any selected text; the edit remains undoable with Ctrl+Z.

## Rendering and tests

Marked 17.0.5 supplies Markdown tokens. Rendering creates fixed DOM nodes with text content; model output never becomes arbitrary HTML or JavaScript. Raw HTML is displayed as text. Links and images are represented as text, and message content cannot initiate network requests. Code blocks support syntax highlighting, soft wrapping, optional visual line numbers and folding; line numbers never enter the copied, opened or inserted source. The bundled Marked license is in `vendor/marked.LICENSE.md`.

- `tools/verify-agent-web-messages.cjs` checks Markdown links, safe external-link dispatch, whole-answer and code copy, quoted text/code follow-ups, draft transactions, cancellable history removal, IME handling, selection retention, font settings, IDE context summaries, exact context previews and opt-out, duplicate attachment disambiguation, approval retry and path scope, composer-aware scrolling, structured tools, safe rendering and responsive layouts. `AgentProtocolSmoke.dpr` also checks native HTTP(S) URL validation against unsafe schemes, credentials, missing hosts and control characters.
- `Source/Tests/AgentWebPanelSmoke.dpr` checks native startup, visibility transitions, host dispatch, Unicode drafts, tool persistence, resizing and teardown.
- `Source/Tests/AgentWebControlSmoke.dpr` checks parent guard, bridge roundtrip and destruction during asynchronous initialization.
- `Source/Tests/AgentMainSmoke.dpr` checks approval decisions, clipboard routing, session persistence, history removal and project isolation.

Native IME behavior and visual acceptance on other DPI settings require testing on the target desktop.
