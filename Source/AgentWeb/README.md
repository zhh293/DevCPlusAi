# AI panel web renderer

Visibility fix: the native controller now synchronizes `IsVisible` with the parent HWND during refresh, including the initial hidden-to-visible transition. The host no longer repeatedly calls BringToFront on each polling tick. The native panel smoke test now queries the controller and verifies hidden/show/hide/show transitions; all passed. This specifically covers a gap in the earlier hidden-host tests, which proved navigation but not actual controller visibility.

The production `AgentPanel` now starts this renderer automatically when `AgentWebHost.dll` and `AgentWeb/index.html` are beside the executable. `tools/deploy-agent-web.ps1` builds the x86 bridge and stages these assets; `tools/build-windows.ps1` also invokes deployment. Keep the DLL and whole `AgentWeb` directory with `devcpp.exe`.

`AgentPanelWeb.inc` adapts existing timeline/history records to stable message IDs, sends only changed blocks, synchronizes drafts, sessions, attachments and theme, and queues browser actions for the VCL timer instead of opening modal dialogs from COM callbacks. Sending, stopping, settings, attachments, quick actions and sessions use the existing handlers. Command approval remains in the existing agent host. The native controls remain as the persistence adapter and fallback when the browser cannot initialize.

`AgentWebPanelSmoke.dpr` passed against the real production page: startup, message/tool snapshots, Unicode draft, settings dispatch, protocol-version rejection, resizing, clearing and teardown. Browser renderer tests also passed after integration. The existing full integration suite passed on the first build; a subsequent run timed out in `AgentMainSmoke`. End-user visual and interaction acceptance is pending user testing.

`preview.html` is an interactive layout prototype, not the shipping UI. It uses fixed example content and never sends a model request or executes commands. Native actions are explicitly labelled as prototype-only. Six states, three widths and light/dark themes can be selected from the preview toolbar.

`Native/AgentWebHost.cpp` is an experimental x86 C ABI bridge. Delphi owns the parent window and calls create/resize/post/close on the same STA thread. Native asynchronous callbacks retain their state; closing marks that state inactive and suppresses callbacks into Delphi. Navigation is restricted to the initial local page and new windows are suppressed. The DLL must remain loaded until process exit because pending COM callbacks can still contain DLL code. Model output must never be passed to an executable script interface.

The bridge statically links the Microsoft SDK loader, not the WebView2 browser runtime. The final distribution will need runtime detection and a documented installation path. The local machine has an installed runtime; this does not prove availability on clean Windows installations.

## Evidence, 2026-09-17

- `index.html`, `panel.css`, `messages.js` and `panel.js` now provide the message renderer and versioned host protocol, separate from the fixture-based preview. Markdown is tokenized with locally bundled Marked 17.0.5 and rendered using DOM creation/textContent only. Raw HTML is displayed as text; remote images and clickable links are not activated yet.
- `tools/verify-agent-web-messages.cjs` checks real Markdown tables/nested lists/code, HTML injection, stable message order, tool expansion through updates, follow-at-bottom vs reading older messages, composing Enter, send acknowledgment and 320/480/800 px layouts. Passed on Edge; screenshot `.tools/ui-redesign/messages.png` was visually inspected.
- `Source/Tests/AgentWebControlSmoke.dpr` checks the reusable `TAgentWebView`: missing-parent guard, Unicode roundtrip, resize, stop and destruction during asynchronous initialization. Passed with Delphi 7 x86.

- Browser prototype: 36 layout cases (six states × three widths × two themes), tool folding, deny action, input treated as text, composing Enter and attachment removal are checked by `tools/verify-agent-web-preview.cjs`.
- Delphi 7 probe: x86 DLL loaded in a real VCL parent, local HTML navigation, width changes, Unicode host-to-page-to-host roundtrip and close passed on the development machine.
- SDK used for experiment: Microsoft.Web.WebView2 1.0.4191.47, downloaded from the NuGet flat-container endpoint to `.tools/webview-sdk/extracted`.
- SDK archive SHA-256: `F492BBF547D0DA329553B6727435B677579B1E9F91CC9E4A1AD029366D5F23D0`.
- Compiler: MSVC x86 bridge and Delphi 7 VCL host. `tools/build-agent-web-probe.cmd` is a local developer probe script, not the production build pipeline.

## Not yet complete

- The original preview still uses fixtures; the new renderer parses Markdown and updates message blocks. Full streaming selection retention and large-history performance still require work.
- The production AgentPanel now uses the renderer when its runtime assets are present. The rebuilt root executable includes the integration.
- Native focus/IME input, clipboard images, accessibility and runtime missing/error behavior require further testing. Browser event simulation is not a substitute for native IME testing.
- Existing history remains in its original format and is adapted for display. A future standalone web data model can remove the native rendering work currently retained for compatibility. Installer/distribution packaging outside the local build still needs to include the new runtime assets.
- Current probe settings/navigation controls are not a complete security review of a production renderer. Files and external links need explicit host-side policies before activation.

## Upstream references

- [Microsoft runtime distribution](https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution)
- [Microsoft Win32 setup](https://learn.microsoft.com/microsoft-edge/webview2/get-started/win32)

## Renderer protocol v1

All packets contain `version: 1`. Host-to-view packets are delivered through WebView2 `PostWebMessageAsJson`:

- `state`: `busy`, `status`, `model`, `theme` (`dark` or `light`). Enables the composer after host initialization.
- `upsert`: `item` with stable `id`, immutable `kind` (`user`, `assistant`, `tool`, `system`), complete `text`, optional tool `name` and `status`. First insertion determines chronological position; subsequent updates preserve that position and tool expansion. Send cumulative text, not a delta.
- `reset`: clears messages and pending updates when changing conversations.
- `accepted`: clears composer text only after the host accepted the send request. Failed sends must not emit this packet.

View-to-host packets are JSON strings with `action`: `ready`, `send` (plus `text`), `stop`, `history`, `new`, `settings`, `attach`. The host must validate the schema and current application state and route actions through existing application handlers. No packet authorizes command execution or bypasses approval.

Marked is vendored from the installed 17.0.5 package; its MIT license is included at `vendor/marked.LICENSE.md`. The renderer does not use Marked's HTML output. It builds a fixed set of DOM elements from tokens, with no arbitrary attributes, HTML insertion, network requests or script execution from message content.
