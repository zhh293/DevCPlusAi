# AI panel web renderer: implementation work in progress

`preview.html` is an interactive layout prototype, not the shipping UI. It uses fixed example content and never sends a model request or executes commands. Native actions are explicitly labelled as prototype-only. Six states, three widths and light/dark themes can be selected from the preview toolbar.

`Native/AgentWebHost.cpp` is an experimental x86 C ABI bridge. Delphi owns the parent window and calls create/resize/post/close on the same STA thread. Native asynchronous callbacks retain their state; closing marks that state inactive and suppresses callbacks into Delphi. Navigation is restricted to the initial local page and new windows are suppressed. The DLL must remain loaded until process exit because pending COM callbacks can still contain DLL code. Model output must never be passed to an executable script interface.

The bridge statically links the Microsoft SDK loader, not the WebView2 browser runtime. The final distribution will need runtime detection and a documented installation path. The local machine has an installed runtime; this does not prove availability on clean Windows installations.

## Evidence, 2026-09-17

- Browser prototype: 36 layout cases (six states × three widths × two themes), tool folding, deny action, input treated as text, composing Enter and attachment removal are checked by `tools/verify-agent-web-preview.cjs`.
- Delphi 7 probe: x86 DLL loaded in a real VCL parent, local HTML navigation, width changes, Unicode host-to-page-to-host roundtrip and close passed on the development machine.
- SDK used for experiment: Microsoft.Web.WebView2 1.0.4191.47, downloaded from the NuGet flat-container endpoint to `.tools/webview-sdk/extracted`.
- SDK archive SHA-256: `F492BBF547D0DA329553B6727435B677579B1E9F91CC9E4A1AD029366D5F23D0`.
- Compiler: MSVC x86 bridge and Delphi 7 VCL host. `tools/build-agent-web-probe.cmd` is a local developer probe script, not the production build pipeline.

## Not yet complete

- The prototype does not parse streamed Markdown. Its sample table and code are actual HTML but currently pre-rendered fixtures.
- The production AgentPanel has not switched to the new renderer. Existing `devcpp.exe` is unchanged by this experiment.
- Native focus/IME input, clipboard images, accessibility, runtime missing/error behavior and close-during-initialization require further testing.
- Rendering model, stable IDs, history migration, streaming, approval integration, host command validation and release packaging remain implementation tasks.
- Current probe settings/navigation controls are not a complete security review of a production renderer. Files and external links need explicit host-side policies before activation.

## Upstream references

- [Microsoft runtime distribution](https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution)
- [Microsoft Win32 setup](https://learn.microsoft.com/microsoft-edge/webview2/get-started/win32)
