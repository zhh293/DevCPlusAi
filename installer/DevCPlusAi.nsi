Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "Sections.nsh"
!include "x64.nsh"
!include "StrFunc.nsh"
${StrStr}

!ifndef PRODUCT_KEY
!define PRODUCT_KEY "DevCPlusAi"
!endif
!ifndef SHORTCUT_NAME
!define SHORTCUT_NAME "DevCPlusAi"
!endif
!define REG_UNINSTALL "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_KEY}"
!define WEBVIEW_KEY "Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"

Name "DevCPlusAi ${VERSION}"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\DevCPlusAi"
InstallDirRegKey HKCU "Software\${PRODUCT_KEY}" "InstallDir"
RequestExecutionLevel user
ManifestDPIAware true
; Independent blocks allow unchecked components to be skipped without decoding.
SetCompressor /FINAL zlib
ShowInstDetails show
ShowUninstDetails show
VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductName" "DevCPlusAi"
VIAddVersionKey /LANG=1033 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "FileDescription" "DevCPlusAi Windows Setup"
VIAddVersionKey /LANG=1033 "LegalCopyright" "DevCPlusAi contributors; GPL"
!define MUI_ICON "${PAYLOAD}\RedPanda.ico"
!define MUI_UNICON "${PAYLOAD}\RedPanda.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\devcpp.exe"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!define MUI_FINISHPAGE_TEXT "安装完成。可从开始菜单搜索 DevCPlusAi 启动。$\r$\n$\r$\n需要补装编译器或 AI 助手时，可重新运行此安装包并勾选组件。AI 对话需填写自己的 API Key。"
!define MUI_UNCONFIRMPAGE_TEXT_TOP "卸载程序文件和快捷方式。你的配置、对话记录及自行保存的源码将保留。"
!ifdef ONLINE_WEBVIEW
!define MUI_COMPONENTSPAGE_TEXT_TOP "选择要安装的组件。编译器和 AI 组件已随包提供；首次安装 AI 助手可能需要联网下载 WebView2。未勾选的现有组件会保留。"
!else
!define MUI_COMPONENTSPAGE_TEXT_TOP "选择要安装的组件。所有运行组件均已包含，可离线安装。未勾选的现有组件会保留。"
!endif
InstType "完整安装（推荐）"
InstType "C/C++ 开发（不含 AI）"
InstType "AI 助手（使用已有编译器）"
InstType "仅编辑器"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${PAYLOAD}\LICENSE"
!insertmacro MUI_PAGE_COMPONENTS
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE ValidateDirectory
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

Var WebViewVersion
Var Arguments
Var InstallMode
!ifdef TEST_BUILD
Var TestWebView
Var TestWebViewInstalled
!endif

; Run prerequisites before writing any application files.
Section "-Prepare"
  SectionIn 1 2 3 4 RO
  Call ValidateDirectory
  Call PrepareWebView
SectionEnd

Section "DevCPlusAi 编辑器（必选）" Core
  SectionIn 1 2 3 4 RO
  SetOutPath "$INSTDIR"
  SetOverwrite on
  File /r /x MinGW64 /x nodejs /x claude-cli /x AgentWeb /x AgentWebHost.dll /x AGENT-RUNTIME-VERSIONS.txt "${PAYLOAD}\*"
SectionEnd

Section "C/C++ 编译器（MinGW64，约 437 MB）" Compiler
  SectionIn 1 2
  SetOutPath "$INSTDIR\MinGW64"
  File /r "${PAYLOAD}\MinGW64\*"
SectionEnd

Section "AI 助手（原生 Claude CLI）" AI
  SectionIn 1 3
  SetOutPath "$INSTDIR"
  File "${PAYLOAD}\AgentWebHost.dll"
  File "${PAYLOAD}\AGENT-RUNTIME-VERSIONS.txt"
  File /r "${PAYLOAD}\AgentWeb"
  File /r "${PAYLOAD}\claude-cli"
SectionEnd

Section "桌面快捷方式" DesktopShortcut
  SectionIn 1 2 3 4
  SetOutPath "$INSTDIR"
  CreateShortcut "$DESKTOP\${SHORTCUT_NAME}.lnk" "$INSTDIR\devcpp.exe" "" "$INSTDIR\devcpp.exe" 0
SectionEnd

Section "-Register"
  SectionIn 1 2 3 4 RO
  SetOutPath "$INSTDIR"
  ; Preserve unchecked existing components on upgrade and all user settings.
  WriteINIStr "$INSTDIR\installation.ini" "Components" "AI" "0"
  IfFileExists "$INSTDIR\claude-cli\bin\claude.exe" 0 noAI
  IfFileExists "$INSTDIR\AgentWebHost.dll" 0 noAI
  WriteINIStr "$INSTDIR\installation.ini" "Components" "AI" "1"
noAI:
  WriteINIStr "$INSTDIR\installation.ini" "Components" "Compiler" "0"
  IfFileExists "$INSTDIR\MinGW64\bin\g++.exe" 0 noCompiler
  WriteINIStr "$INSTDIR\installation.ini" "Components" "Compiler" "1"
noCompiler:
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\${PRODUCT_KEY}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${REG_UNINSTALL}" "DisplayName" "DevCPlusAi"
  WriteRegStr HKCU "${REG_UNINSTALL}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${REG_UNINSTALL}" "Publisher" "DevCPlusAi contributors"
  WriteRegStr HKCU "${REG_UNINSTALL}" "DisplayIcon" "$INSTDIR\devcpp.exe,0"
  WriteRegStr HKCU "${REG_UNINSTALL}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${REG_UNINSTALL}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "${REG_UNINSTALL}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegStr HKCU "${REG_UNINSTALL}" "URLInfoAbout" "https://github.com/zhh293/DevCPlusAi"
  WriteRegDWORD HKCU "${REG_UNINSTALL}" "NoModify" 1
  WriteRegDWORD HKCU "${REG_UNINSTALL}" "NoRepair" 1
  ; Calculate the actual installed tree, including retained optional components.
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKCU "${REG_UNINSTALL}" "EstimatedSize" $0
  CreateDirectory "$SMPROGRAMS\${SHORTCUT_NAME}"
  CreateShortcut "$SMPROGRAMS\${SHORTCUT_NAME}\DevCPlusAi.lnk" "$INSTDIR\devcpp.exe" "" "$INSTDIR\devcpp.exe" 0
  CreateShortcut "$SMPROGRAMS\${SHORTCUT_NAME}\卸载 DevCPlusAi.lnk" "$INSTDIR\Uninstall.exe"
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${Core} "编辑器、语法高亮、项目管理、开始菜单入口和卸载程序。"
  !insertmacro MUI_DESCRIPTION_TEXT ${Compiler} "勾选后即可编译、运行和调试 C/C++。不勾选时需要自行指定已有编译器。"
  !insertmacro MUI_DESCRIPTION_TEXT ${AI} "安装 AI 对话界面和原生 Claude CLI，无需另装 Node.js。需要 WebView2 和自己的 API Key；未安装时不弹出 AI 设置向导。"
  !insertmacro MUI_DESCRIPTION_TEXT ${DesktopShortcut} "在当前用户桌面添加启动快捷方式。"
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Function .onInit
  SetShellVarContext current
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "此安装包需要 64 位 Windows。" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
  ${GetParameters} $Arguments
  ClearErrors
  ${GetOptions} $Arguments "/COMPONENTS=" $InstallMode
  ${IfNot} ${Errors}
    ${If} $InstallMode == "all"
      SetCurInstType 0
    ${ElseIf} $InstallMode == "cpp"
      SetCurInstType 1
    ${ElseIf} $InstallMode == "ai"
      SetCurInstType 2
    ${ElseIf} $InstallMode == "editor"
      SetCurInstType 3
    ${Else}
      MessageBox MB_ICONSTOP "无效的组件选项。请使用 all、cpp、ai 或 editor。" /SD IDOK
      SetErrorLevel 1
      Abort
    ${EndIf}
  ${EndIf}
  ClearErrors
  ${GetOptions} $Arguments "/NODESKTOP" $0
  ${IfNot} ${Errors}
    !insertmacro UnselectSection ${DesktopShortcut}
  ${EndIf}
!ifdef TEST_BUILD
  ${GetOptions} $Arguments "/TESTWEBVIEW=" $TestWebView
!endif
FunctionEnd

Function ValidateDirectory
  ${StrStr} $0 "$INSTDIR" "%"
  ${StrStr} $1 "$INSTDIR" "#"
  ${If} $0 != ""
  ${OrIf} $1 != ""
    MessageBox MB_ICONSTOP "编译器安装路径不能包含 % 或 #。请选择其他文件夹。" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
  IfFileExists "$INSTDIR\devcpp.exe" 0 done
  System::Call 'kernel32::CreateFileW(w "$INSTDIR\devcpp.exe", i 0x40000000, i 1, p 0, i 3, i 0, p 0) p.r0'
  ${If} $0 == -1
    MessageBox MB_ICONSTOP "目标目录中的 DevCPlusAi 正在运行或不可写。请保存代码并关闭程序后重新安装。" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
  System::Call 'kernel32::CloseHandle(p r0)'
done:
FunctionEnd

Function CheckWebView
!ifdef TEST_BUILD
  ${If} $TestWebView == "fail"
    StrCpy $WebViewVersion ""
    Return
  ${ElseIf} $TestWebView == "success"
    StrCpy $WebViewVersion $TestWebViewInstalled
    Return
  ${EndIf}
!endif
  SetRegView 32
  ReadRegStr $WebViewVersion HKLM "${WEBVIEW_KEY}" "pv"
  ${If} $WebViewVersion == ""
  ${OrIf} $WebViewVersion == "0.0.0.0"
    ReadRegStr $WebViewVersion HKCU "${WEBVIEW_KEY}" "pv"
  ${EndIf}
FunctionEnd

Function PrepareWebView
  ${IfNot} ${SectionIsSelected} ${AI}
    Return
  ${EndIf}
retry:
  Call CheckWebView
  ${If} $WebViewVersion != ""
  ${AndIf} $WebViewVersion != "0.0.0.0"
    DetailPrint "已安装 WebView2，跳过下载和安装。"
    Return
  ${EndIf}
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File /oname=WebView2Runtime.exe "${WEBVIEW_INSTALLER}"
!ifdef ONLINE_WEBVIEW
  DetailPrint "正在从 Microsoft 下载并安装 WebView2，请保持网络连接…"
!else
  DetailPrint "正在安装 Microsoft Edge WebView2 Runtime…"
!endif
!ifdef TEST_BUILD
  ${If} $TestWebView == "fail"
    StrCpy $0 99
  ${ElseIf} $TestWebView == "success"
    StrCpy $0 0
    StrCpy $TestWebViewInstalled "1.0.0.0"
  ${Else}
!endif
    ExecWait '"$PLUGINSDIR\WebView2Runtime.exe" /silent /install' $0
!ifdef TEST_BUILD
  ${EndIf}
!endif
  Call CheckWebView
  ${If} $WebViewVersion == ""
  ${OrIf} $WebViewVersion == "0.0.0.0"
    MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "WebView2 安装未完成（退出码 $0）。$\r$\n$\r$\n请检查网络后重试，或取消并使用离线安装包。也可重新运行安装包，暂不勾选 AI 助手。" /SD IDCANCEL IDRETRY retry
    SetErrorLevel 1
    Abort
  ${EndIf}
FunctionEnd

Function un.onInit
  SetShellVarContext current
  IfFileExists "$INSTDIR\devcpp.exe" 0 done
  System::Call 'kernel32::CreateFileW(w "$INSTDIR\devcpp.exe", i 0x40000000, i 1, p 0, i 3, i 0, p 0) p.r0'
  ${If} $0 == -1
    MessageBox MB_ICONSTOP "请保存代码并关闭此目录中的 DevCPlusAi 后再卸载。" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
  System::Call 'kernel32::CloseHandle(p r0)'
done:
FunctionEnd

Section "Uninstall"
  !include "${DELETE_MANIFEST}"
  Delete "$INSTDIR\installation.ini"
  Delete "$SMPROGRAMS\${SHORTCUT_NAME}\DevCPlusAi.lnk"
  Delete "$SMPROGRAMS\${SHORTCUT_NAME}\卸载 DevCPlusAi.lnk"
  RMDir "$SMPROGRAMS\${SHORTCUT_NAME}"
  Delete "$DESKTOP\${SHORTCUT_NAME}.lnk"
  DeleteRegKey HKCU "${REG_UNINSTALL}"
  DeleteRegKey HKCU "Software\${PRODUCT_KEY}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
