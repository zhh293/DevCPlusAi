Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
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
SetCompressor /SOLID lzma
SetCompressorDictSize 32
ShowInstDetails show
ShowUninstDetails show
VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductName" "DevCPlusAi"
VIAddVersionKey /LANG=1033 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "FileDescription" "DevCPlusAi Windows Setup (with GCC)"
VIAddVersionKey /LANG=1033 "LegalCopyright" "DevCPlusAi contributors; GPL"
!define MUI_ICON "${PAYLOAD}\RedPanda.ico"
!define MUI_UNICON "${PAYLOAD}\RedPanda.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\devcpp.exe"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!define MUI_FINISHPAGE_TEXT "安装完成。可从开始菜单搜索 DevCPlusAi 启动。$\r$\n$\r$\n已包含 C/C++ 编译器和 AI 运行组件。AI 对话需在程序中填写自己的服务商与 API Key。"
!define MUI_UNCONFIRMPAGE_TEXT_TOP "卸载程序文件和快捷方式。你的配置、对话记录及自行保存的源码将保留。"
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

Function .onInit
  SetShellVarContext current
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "此安装包需要 64 位 Windows。"
    SetErrorLevel 1
    Abort
  ${EndIf}
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
  SetRegView 32
  ReadRegStr $WebViewVersion HKLM "${WEBVIEW_KEY}" "pv"
  ${If} $WebViewVersion == ""
  ${OrIf} $WebViewVersion == "0.0.0.0"
    ReadRegStr $WebViewVersion HKCU "${WEBVIEW_KEY}" "pv"
  ${EndIf}
FunctionEnd

Section "DevCPlusAi + C/C++ 编译器 + AI 助手（必选）" Main
  SectionIn RO
  Call ValidateDirectory
  Call CheckWebView
  ${If} $WebViewVersion == ""
  ${OrIf} $WebViewVersion == "0.0.0.0"
    InitPluginsDir
    SetOutPath "$PLUGINSDIR"
    File /oname=WebView2Runtime.exe "${WEBVIEW_INSTALLER}"
    DetailPrint "正在安装 Microsoft Edge WebView2 Runtime…"
    ExecWait '"$PLUGINSDIR\WebView2Runtime.exe" /silent /install' $0
    Call CheckWebView
    ${If} $WebViewVersion == ""
    ${OrIf} $WebViewVersion == "0.0.0.0"
      MessageBox MB_ICONSTOP "WebView2 Runtime 安装失败（退出码 $0）。请安装此组件后重新运行安装包。" /SD IDOK
      SetErrorLevel 1
      Abort
    ${EndIf}
  ${EndIf}
  SetOutPath "$INSTDIR"
  SetOverwrite on
  File /r "${PAYLOAD}\*"
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
  WriteRegDWORD HKCU "${REG_UNINSTALL}" "EstimatedSize" ${INSTALLED_KB}
  CreateDirectory "$SMPROGRAMS\${SHORTCUT_NAME}"
  CreateShortcut "$SMPROGRAMS\${SHORTCUT_NAME}\DevCPlusAi.lnk" "$INSTDIR\devcpp.exe" "" "$INSTDIR\devcpp.exe" 0
  CreateShortcut "$SMPROGRAMS\${SHORTCUT_NAME}\卸载 DevCPlusAi.lnk" "$INSTDIR\Uninstall.exe"
SectionEnd

Section "桌面快捷方式" DesktopShortcut
  CreateShortcut "$DESKTOP\${SHORTCUT_NAME}.lnk" "$INSTDIR\devcpp.exe" "" "$INSTDIR\devcpp.exe" 0
SectionEnd

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
  ; Generated exact file list. Never recursively remove a user's install tree.
  !include "${DELETE_MANIFEST}"
  Delete "$SMPROGRAMS\${SHORTCUT_NAME}\DevCPlusAi.lnk"
  Delete "$SMPROGRAMS\${SHORTCUT_NAME}\卸载 DevCPlusAi.lnk"
  RMDir "$SMPROGRAMS\${SHORTCUT_NAME}"
  Delete "$DESKTOP\${SHORTCUT_NAME}.lnk"
  DeleteRegKey HKCU "${REG_UNINSTALL}"
  DeleteRegKey HKCU "Software\${PRODUCT_KEY}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
