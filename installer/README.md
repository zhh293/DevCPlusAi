# Windows installer

`tools/package-installer.ps1` builds a per-user Unicode NSIS installer from a
validated compiler ZIP. It refuses a ZIP whose SHA256 or product version differs
from `tools/test-portable-release.ps1`'s successful acceptance report.

```powershell
powershell -ExecutionPolicy Bypass -File tools\build-windows.ps1
powershell -ExecutionPolicy Bypass -File tools\package-portable.ps1 -Version 1.0.3 -PackageType X64Compiler
powershell -ExecutionPolicy Bypass -File tools\package-installer.ps1 -Version 1.0.3 -WebViewMode Online
powershell -ExecutionPolicy Bypass -File tools\package-installer.ps1 -Version 1.0.3 -WebViewMode Offline
```

Dependencies: NSIS 3.11 (`-NsisPath`) and a Microsoft-signed Evergreen WebView2
installer (`-WebViewInstallerPath`). Online mode uses the small Bootstrapper;
Offline mode uses the x64 standalone installer. Defaults use the ignored local
`.tools/nsis/nsis-3.11` and `.tools/downloads` directories. The runtime installer
must pass Authenticode validation as Microsoft Corporation. Its redistribution
and detection follow [Microsoft's WebView2 deployment documentation](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution).

For online builds, save Microsoft's Bootstrapper to
`.tools/downloads/MicrosoftEdgeWebview2Setup.exe`:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile '.tools/downloads/MicrosoftEdgeWebview2Setup.exe'
```

Both variants embed the C/C++ compiler and AI runtime, with independently
selectable NSIS sections. Only WebView2 uses on-demand network installation in
online mode. Deselecting a component reduces installed size, not download size.
WebView2 is checked only when AI is selected, and is installed before any app
files are written. A failed prerequisite supports retry/cancel; silent mode
returns failure without creating app files or product registration.

Silent installation supports `/COMPONENTS=all|cpp|ai|editor` and `/NODESKTOP`.

The AI component uses native `claude-cli/bin/claude.exe` and does not bundle a
separate Node.js distribution. WebView2 renders the chat independently of Node.js.
Custom MCP servers or user projects requiring Node.js must provide their own
runtime. Existing installations are not stripped of their old Node.js directory
during upgrade, to avoid removing a runtime used by user configuration.
Rebuild the portable ZIP before building an installer: legacy ZIPs containing
`nodejs/` are rejected rather than silently included in the core component.
NSIS requires `/D=...` to be the last argument and its path must not be quoted.
The generated `installation.ini` records effective components. On upgrade,
unchecked existing components are retained; personal settings are never reset.

Build an isolated test installer with `-TestBuild`, then exercise all modes:

```powershell
powershell -ExecutionPolicy Bypass -File tools\package-installer.ps1 -Version 1.0.3 -WebViewMode Online -TestBuild
foreach ($mode in @('editor', 'cpp', 'ai', 'all')) {
    powershell -ExecutionPolicy Bypass -File tools\test-installer.ps1 -Version 1.0.3 -WebViewMode Online -Components $mode -TestBuild
    if ($LASTEXITCODE) { throw "Installer test failed: $mode" }
}
```

The test build has a distinct product key and shortcuts. Test-only prerequisite
fault injection is excluded from production installers. Acceptance covers
selected/omitted file hashes, no-AI startup state, shortcuts, compiler and real
WebView panel tests, component addition, reinstallation, locked executables,
uninstallation and preservation of user data.

The installer uses a distinct `DevCPlusAi` registry key and Start Menu folder,
leaving existing Dev-C++ installations alone. It creates optional desktop and
mandatory Start Menu shortcuts, registers Windows app removal, and retains the
portable configuration convention (`config` under the install directory).
GCC installation directories containing `%` or `#` are rejected because the
bundled compiler interprets those characters in its specs/plugin paths.

The uninstaller removes an exact generated list of shipped files and only empty
directories. It does not recursively delete the installation root, remove user
configuration or source files, or uninstall the shared WebView2 runtime.
Do not run the legacy root `devcpp-x64.nsi` to publish DevCPlusAi releases.
