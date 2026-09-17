#include <windows.h>
#include <wrl.h>
#include <string>
#include <memory>
#include "WebView2.h"
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Callback;
using Notify = void (__stdcall *)(void*, int, const wchar_t*);
struct State {
    HWND parent{};
    Notify notify{};
    void* context{};
    std::wstring uri;
    bool closed{};
    ComPtr<ICoreWebView2Controller> controller;
    ComPtr<ICoreWebView2> view;
    void emit(int kind, const wchar_t* text) {
        if (!closed && notify && IsWindow(parent)) notify(context, kind, text);
    }
};
using Handle = std::shared_ptr<State>;
extern "C" __declspec(dllexport) void* __cdecl ABCreate(HWND parent,
    const wchar_t* uri, const wchar_t* data, Notify notify, void* context) {
    if (!IsWindow(parent) || !uri || !data) return nullptr;
    auto s = std::make_shared<State>();
    s->parent = parent; s->uri = uri; s->notify = notify; s->context = context;
    auto hr = CreateCoreWebView2EnvironmentWithOptions(nullptr, data, nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
        [s](HRESULT result, ICoreWebView2Environment* env)->HRESULT {
            if (s->closed) return S_OK;
            if (FAILED(result) || !env) {s->emit(2, L"WebView environment failed"); return S_OK;}
            auto started = env->CreateCoreWebView2Controller(s->parent,
                Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                [s](HRESULT result, ICoreWebView2Controller* controller)->HRESULT {
                    if (s->closed) {if (controller) controller->Close(); return S_OK;}
                    if (FAILED(result) || !controller) {s->emit(2, L"WebView controller failed"); return S_OK;}
                    s->controller = controller;
                    controller->get_CoreWebView2(&s->view);
                    RECT bounds{}; GetClientRect(s->parent, &bounds); controller->put_Bounds(bounds);
                    ComPtr<ICoreWebView2Settings> settings;
                    s->view->get_Settings(&settings);
                    settings->put_AreDevToolsEnabled(FALSE);
                    settings->put_AreDefaultContextMenusEnabled(FALSE);
                    EventRegistrationToken token{};
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
                            if (source && s->uri == source && SUCCEEDED(args->TryGetWebMessageAsString(&text)))
                                s->emit(1, text);
                            CoTaskMemFree(source); CoTaskMemFree(text); return S_OK;
                        }).Get(), &token);
                    s->view->add_NavigationCompleted(Callback<ICoreWebView2NavigationCompletedEventHandler>(
                        [s](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args)->HRESULT {
                            BOOL ok{}; args->get_IsSuccess(&ok); s->emit(ok ? 0 : 2, ok ? L"ready" : L"Navigation failed");
                            return S_OK;
                        }).Get(), &token);
                    s->view->Navigate(s->uri.c_str());
                    return S_OK;
                }).Get());
            if (FAILED(started)) s->emit(2, L"Controller initialization failed");
            return S_OK;
        }).Get());
    if (FAILED(hr)) return nullptr;
    return new Handle(s);
}
extern "C" __declspec(dllexport) void __cdecl ABResize(void* value) {
    if (!value) return; auto s = *static_cast<Handle*>(value);
    if (!s->closed && s->controller && IsWindow(s->parent)) {
        RECT bounds{}; GetClientRect(s->parent, &bounds); s->controller->put_Bounds(bounds);
    }
}
extern "C" __declspec(dllexport) HRESULT __cdecl ABPost(void* value, const wchar_t* json) {
    if (!value || !json) return E_INVALIDARG;
    auto s = *static_cast<Handle*>(value);
    return !s->closed && s->view ? s->view->PostWebMessageAsJson(json) : E_PENDING;
}
extern "C" __declspec(dllexport) void __cdecl ABClose(void* value) {
    if (!value) return; auto handle = static_cast<Handle*>(value); auto s = *handle;
    s->closed = true; s->notify = nullptr;
    if (s->controller) s->controller->Close();
    s->view.Reset(); s->controller.Reset(); delete handle;
}
