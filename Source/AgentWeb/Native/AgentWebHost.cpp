#include <windows.h>
#include <shlwapi.h>
#include <wrl.h>
#include <string>
#include <memory>
#include <vector>
#include "WebView2.h"
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Callback;
using Notify = void (__stdcall *)(void*, int, const wchar_t*);

static std::wstring FilePathFromUri(const wchar_t* uri) {
    if (!uri) return std::wstring();
    DWORD length = 32768;
    std::vector<wchar_t> buffer(length);
    HRESULT result = PathCreateFromUrlW(uri, buffer.data(), &length, 0);
    if (result == E_POINTER && length > buffer.size()) {
        buffer.resize(length + 1);
        result = PathCreateFromUrlW(uri, buffer.data(), &length, 0);
    }
    if (FAILED(result)) return std::wstring();
    return std::wstring(buffer.data());
}

struct State {
    HWND parent{};
    Notify notify{};
    void* context{};
    std::wstring uri;
    std::wstring folder;
    bool closed{};
    bool pageLoaded{};
    ComPtr<ICoreWebView2Controller> controller;
    ComPtr<ICoreWebView2> view;
    void emit(int kind, const wchar_t* text) {
        if (!closed && notify && IsWindow(parent)) notify(context, kind, text);
    }
    void error(const wchar_t* stage, HRESULT result) {
        wchar_t text[256]{};
        swprintf_s(text, L"%s (HRESULT 0x%08X)", stage, static_cast<unsigned>(result));
        emit(2, text);
    }
};
using Handle = std::shared_ptr<State>;
extern "C" __declspec(dllexport) void* __cdecl ABCreate(HWND parent,
    const wchar_t* uri, const wchar_t* data, Notify notify, void* context) {
    if (!IsWindow(parent) || !uri || !data) return nullptr;
    auto s = std::make_shared<State>();
    s->parent = parent; s->notify = notify; s->context = context;
    // Map the Unicode filesystem path directly. Do not round-trip it through
    // ANSI file URLs or compare differently percent-encoded file: addresses.
    std::wstring path = _wcsnicmp(uri, L"file:", 5) == 0 ? FilePathFromUri(uri) : uri;
    const auto slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos || GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES)
        return nullptr;
    s->folder = path.substr(0, slash);
    const auto filename = path.substr(slash + 1);
    // Only a plain HTML entry point is accepted; assets are served from folder.
    if (filename.find_first_of(L"%?#/\\") != std::wstring::npos) return nullptr;
    s->uri = L"https://devcplusai.local/" + filename;
    auto hr = CreateCoreWebView2EnvironmentWithOptions(nullptr, data, nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
        [s](HRESULT result, ICoreWebView2Environment* env)->HRESULT {
            if (s->closed) return S_OK;
            if (FAILED(result) || !env) {s->error(L"WebView environment failed", result); return S_OK;}
            LPWSTR runtimeVersion{};
            if (SUCCEEDED(env->get_BrowserVersionString(&runtimeVersion))) s->emit(3, runtimeVersion);
            CoTaskMemFree(runtimeVersion);
            auto started = env->CreateCoreWebView2Controller(s->parent,
                Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                [s](HRESULT result, ICoreWebView2Controller* controller)->HRESULT {
                    if (s->closed) {if (controller) controller->Close(); return S_OK;}
                    if (FAILED(result) || !controller) {s->error(L"WebView controller failed", result); return S_OK;}
                    s->controller = controller;
                    controller->get_CoreWebView2(&s->view);
                    ComPtr<ICoreWebView2_3> view3;
                    HRESULT mapped = s->view.As(&view3);
                    if (SUCCEEDED(mapped)) mapped = view3->SetVirtualHostNameToFolderMapping(
                        L"devcplusai.local", s->folder.c_str(), COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY);
                    if (FAILED(mapped)) {s->error(L"Local web assets mapping failed", mapped); return S_OK;}
                    RECT bounds{}; GetClientRect(s->parent, &bounds); controller->put_Bounds(bounds);
                    controller->put_IsVisible(IsWindowVisible(s->parent));
                    ComPtr<ICoreWebView2Settings> settings;
                    s->view->get_Settings(&settings);
                    settings->put_AreDevToolsEnabled(FALSE);
                    settings->put_AreDefaultContextMenusEnabled(FALSE);
                    EventRegistrationToken token{};
                    s->view->add_ProcessFailed(Callback<ICoreWebView2ProcessFailedEventHandler>(
                        [s](ICoreWebView2*, ICoreWebView2ProcessFailedEventArgs*)->HRESULT {
                            s->emit(2, L"Browser process failed. Retry the AI chat renderer.");
                            return S_OK;
                        }).Get(), &token);
                    s->view->add_NavigationStarting(Callback<ICoreWebView2NavigationStartingEventHandler>(
                        [s](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args)->HRESULT {
                            LPWSTR uri{}; args->get_Uri(&uri);
                            if (s->closed || !uri || s->uri != uri) args->put_Cancel(TRUE);
                            CoTaskMemFree(uri); return S_OK;
                        }).Get(), &token);
                    s->view->add_NewWindowRequested(Callback<ICoreWebView2NewWindowRequestedEventHandler>(
                        [](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args)->HRESULT {
                            args->put_Handled(TRUE); return S_OK;
                        }).Get(), &token);
                    s->view->add_WebMessageReceived(Callback<ICoreWebView2WebMessageReceivedEventHandler>(
                        [s](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs* args)->HRESULT {
                            LPWSTR source{}, text{}; args->get_Source(&source);
                            // DOM startup can post before NavigationCompleted. Queue
                            // trusted-page messages immediately so ready is not lost.
                            if (source && s->uri == source &&
                                SUCCEEDED(args->TryGetWebMessageAsString(&text)))
                                s->emit(1, text);
                            CoTaskMemFree(source); CoTaskMemFree(text); return S_OK;
                        }).Get(), &token);
                    s->view->add_NavigationCompleted(Callback<ICoreWebView2NavigationCompletedEventHandler>(
                        [s](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args)->HRESULT {
                            BOOL ok{}; args->get_IsSuccess(&ok); s->pageLoaded = ok != FALSE;
                            if (ok) s->emit(0, L"ready");
                            else {
                                COREWEBVIEW2_WEB_ERROR_STATUS status{};
                                args->get_WebErrorStatus(&status);
                                wchar_t text[128]{};
                                swprintf_s(text, L"Local chat navigation failed (WebErrorStatus %d)", static_cast<int>(status));
                                s->emit(2, text);
                            }
                            return S_OK;
                        }).Get(), &token);
                    HRESULT navigated = s->view->Navigate(s->uri.c_str());
                    if (FAILED(navigated)) s->error(L"Navigate failed", navigated);
                    return S_OK;
                }).Get());
            if (FAILED(started)) s->error(L"Controller initialization failed", started);
            return S_OK;
        }).Get());
    if (FAILED(hr)) return nullptr;
    return new Handle(s);
}
extern "C" __declspec(dllexport) void __cdecl ABResize(void* value) {
    if (!value) return; auto s = *static_cast<Handle*>(value);
    if (!s->closed && s->controller && IsWindow(s->parent)) {
        RECT bounds{}; GetClientRect(s->parent, &bounds); s->controller->put_Bounds(bounds);
        s->controller->put_IsVisible(IsWindowVisible(s->parent));
        s->controller->NotifyParentWindowPositionChanged();
    }
}
extern "C" __declspec(dllexport) HRESULT __cdecl ABPost(void* value, const wchar_t* json) {
    if (!value || !json) return E_INVALIDARG;
    auto s = *static_cast<Handle*>(value);
    return !s->closed && s->view ? s->view->PostWebMessageAsJson(json) : E_PENDING;
}
extern "C" __declspec(dllexport) int __cdecl ABIsVisible(void* value) {
    if (!value) return 0;
    auto s = *static_cast<Handle*>(value);
    BOOL visible = FALSE;
    if (!s->closed && s->controller) s->controller->get_IsVisible(&visible);
    return visible ? 1 : 0;
}
extern "C" __declspec(dllexport) void __cdecl ABClose(void* value) {
    if (!value) return; auto handle = static_cast<Handle*>(value); auto s = *handle;
    s->closed = true; s->pageLoaded = false; s->notify = nullptr;
    if (s->controller) s->controller->Close();
    s->view.Reset(); s->controller.Reset(); delete handle;
}
