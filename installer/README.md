# Windows installer

`tools/package-installer.ps1` builds a per-user Unicode NSIS installer from a
validated compiler ZIP. It refuses a ZIP whose SHA256 or product version differs
from `tools/test-portable-release.ps1`'s successful acceptance report.

```powershell
powershell -ExecutionPolicy Bypass -File tools\build-windows.ps1
powershell -ExecutionPolicy Bypass -File tools\package-portable.ps1 -Version 1.0.2 -PackageType X64Compiler
powershell -ExecutionPolicy Bypass -File tools\package-installer.ps1 -Version 1.0.2
```

Dependencies: NSIS 3.11 (`-NsisPath`) and the Microsoft-signed Evergreen WebView2
x64 offline installer (`-WebViewInstallerPath`). Defaults use the ignored local
`.tools/nsis/nsis-3.11` and `.tools/downloads` directories. The runtime installer
must pass Authenticode validation as Microsoft Corporation. Its redistribution
and detection follow [Microsoft's WebView2 deployment documentation](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution).

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
