#include "platform_bridge.h"
#include "clipboard_native.h"
#include "flutter_window.h"
#include "resource.h"
#include "desktop_drag_source.h"
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <shlobj.h>
#include <dwmapi.h>
#include <vector>
#include <map>
#include <algorithm>
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
namespace {
constexpr UINT kTray = WM_APP + 31;
constexpr UINT_PTR kClipboardRetry = 42;
constexpr UINT_PTR kTrayVisibility = 43;
constexpr UINT_PTR kReceiverPoll = 44;
constexpr UINT kReceiverInput = WM_APP + 32;
constexpr int kPopoverHotkey = 100, kTransferHotkey = 101;
struct Shortcut { UINT modifiers = MOD_CONTROL | MOD_ALT, key = 0; bool enabled = true; };
std::map<int, Shortcut> shortcuts;
HWND receiver_window = nullptr;
HWND receiver_probe = nullptr;
bool receiver_file_drag = false;
bool receiver_probe_checked = false;
bool receiver_probe_engaged = false;
HHOOK receiver_mouse_hook = nullptr;
bool exporting_drag = false;
POINT drag_origin{};
HWND drag_source_window = nullptr;
bool desktop_origin_checked = false;
bool mouse_was_down = false;
bool mouse_hook_down = false;
bool receiver_drag_cancelled = false;
HHOOK receiver_keyboard_hook = nullptr;
ULONG_PTR receiver_press_count = 0;
ULONGLONG drag_started_at = 0;
ULONGLONG receiver_released_at = 0;
bool receiver_targeted = false;
void PollReceiver();
int tray_visibility_attempts = 0;
std::map<std::string, PlatformBridge*> bridges;
std::vector<std::unique_ptr<FlutterWindow>> extra_windows;
Value shared_state;
NOTIFYICONDATA tray{};
bool quitting = false;
int clipboard_retries = 0;
DWORD observed_sequence = 0;
UINT taskbar_created = RegisterWindowMessage(L"TaskbarCreated");
UINT show_main = RegisterWindowMessage(L"SuperClipboard.ShowMain");
bool Bool(const Map& m, const char* key) {
  auto it = m.find(Value(key));
  return it != m.end() && std::holds_alternative<bool>(it->second) && std::get<bool>(it->second);
}
bool SetShortcut(HWND window, int id, const Map& value) {
  Shortcut next;
  next.enabled = Bool(value, "enabled");
  auto integer = [&](const char* key) -> UINT {
    auto it = value.find(Value(key));
    if (it == value.end()) return 0;
    if (auto n = std::get_if<int32_t>(&it->second)) return static_cast<UINT>(*n);
    if (auto n = std::get_if<int64_t>(&it->second)) return static_cast<UINT>(*n);
    return 0;
  };
  next.modifiers = integer("modifiers"); next.key = integer("key");
  if (next.enabled && (!next.key || !(next.modifiers & (MOD_CONTROL | MOD_ALT | MOD_WIN)))) return false;
  const auto previous = shortcuts.find(id);
  const auto old = previous == shortcuts.end() ? Shortcut{0, 0, false} : previous->second;
  UnregisterHotKey(window, id);
  if (next.enabled && !RegisterHotKey(window, id, next.modifiers | MOD_NOREPEAT, next.key)) {
    if (old.enabled && old.key) RegisterHotKey(window, id, old.modifiers | MOD_NOREPEAT, old.key);
    return false;
  }
  shortcuts[id] = next;
  return true;
}
LRESULT CALLBACK ReceiverMouseProc(int code, WPARAM message, LPARAM data) {
  if (code == HC_ACTION && receiver_window) {
    const auto* mouse = reinterpret_cast<const MSLLHOOKSTRUCT*>(data);
    if (message == WM_LBUTTONDOWN) {
      mouse_hook_down = true;
      receiver_drag_cancelled = false;
      SetProp(receiver_window, L"SuperClipboard.MousePressCount", reinterpret_cast<HANDLE>(++receiver_press_count));
      drag_origin = mouse->pt;
      drag_source_window = WindowFromPoint(drag_origin);
      desktop_origin_checked = false;
      drag_started_at = GetTickCount64();
      receiver_file_drag = false;
      receiver_probe_checked = false;
    } else if (message == WM_LBUTTONUP) {
      mouse_hook_down = false;
      receiver_released_at = GetTickCount64();
    }
    // Keep the hook short. Our own window handles visibility asynchronously.
    if (message == WM_MOUSEMOVE || message == WM_LBUTTONDOWN || message == WM_LBUTTONUP) {
      PostMessage(receiver_window, kReceiverInput, 0, 0);
    }
  }
  return CallNextHookEx(receiver_mouse_hook, code, message, data);
}
LRESULT CALLBACK ReceiverKeyboardProc(int code, WPARAM message, LPARAM data) {
  if (code == HC_ACTION && (message == WM_KEYDOWN || message == WM_SYSKEYDOWN) &&
      reinterpret_cast<const KBDLLHOOKSTRUCT*>(data)->vkCode == VK_ESCAPE) {
    receiver_drag_cancelled = true;
    if (receiver_window) PostMessage(receiver_window, kReceiverInput, 0, 0);
  }
  return CallNextHookEx(receiver_keyboard_hook, code, message, data);
}
LRESULT CALLBACK ReceiverProc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
  if ((message == WM_TIMER && wp == kReceiverPoll) || message == kReceiverInput) {
    PollReceiver(); return 0;
  }
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  if (message == WM_PAINT) {
    PAINTSTRUCT paint; auto dc = BeginPaint(hwnd, &paint);
    RECT rect; GetClientRect(hwnd, &rect);
    auto brush = CreateSolidBrush(RGB(235, 242, 252)); FillRect(dc, &rect, brush); DeleteObject(brush);
    SetBkMode(dc, TRANSPARENT); SetTextColor(dc, RGB(31, 71, 137));
    const int size = -MulDiv(13, GetDpiForWindow(hwnd), 72);
    auto font = CreateFont(size, 0, 0, 0, FW_MEDIUM, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
      OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Microsoft YaHei UI");
    auto old = SelectObject(dc, font);
    const auto dpi = GetDpiForWindow(hwnd);
    RECT title = rect;
    title.top += MulDiv(18, dpi, 96);
    title.bottom = title.top + MulDiv(26, dpi, 96);
    DrawText(dc, receiver_targeted ? L"松开即可加入中转站" : L"添加到中转站", -1, &title,
      DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    RECT hint = rect;
    hint.top += MulDiv(50, dpi, 96);
    hint.bottom -= MulDiv(10, dpi, 96);
    SetTextColor(dc, RGB(65, 85, 114));
    auto hint_font = CreateFont(-MulDiv(10, dpi, 72), 0, 0, 0, FW_NORMAL,
      FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Microsoft YaHei UI");
    SelectObject(dc, hint_font);
    DrawText(dc, L"拖入文件或文件夹，松手收纳", -1, &hint,
      DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    SelectObject(dc, old); DeleteObject(hint_font); DeleteObject(font); EndPaint(hwnd, &paint); return 0;
  }
  return DefWindowProc(hwnd, message, wp, lp);
}
void PollReceiver() {
  // Hook callbacks preserve real button transitions even when asynchronous key
  // polling is unavailable while the shell desktop owns foreground input.
  const bool down = receiver_mouse_hook ? mouse_hook_down : (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
  POINT point; GetCursorPos(&point);
  if (down && !mouse_was_down && !receiver_mouse_hook) {
    drag_origin = point;
    drag_source_window = WindowFromPoint(drag_origin);
    desktop_origin_checked = false;
    drag_started_at = GetTickCount64();
    receiver_file_drag = false;
    receiver_probe_checked = false;
    receiver_drag_cancelled = false;
  }
  mouse_was_down = down;
  if (!receiver_window) return;
  // OLE calls Drop after processing button-up in the source process. Do not
  // remove its target in the global hook/timer before that callback arrives.
  // Bound the grace period in case the source exits without Drop/DragLeave.
  if (!down && receiver_targeted && !exporting_drag && !receiver_drag_cancelled &&
      GetTickCount64() - receiver_released_at < 750) return;
  if (!down || exporting_drag || receiver_drag_cancelled || (GetAsyncKeyState(VK_ESCAPE) & 0x8000)) {
    receiver_file_drag = false;
    ShowWindow(receiver_window, SW_HIDE);
    if (receiver_probe && !receiver_probe_engaged) ShowWindow(receiver_probe, SW_HIDE);
    return;
  }
  MONITORINFO monitor{sizeof(monitor)};
  GetMonitorInfo(MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST), &monitor);
  const int scale = static_cast<int>(GetDpiForWindow(receiver_window));
  const int w = MulDiv(250, scale, 96), h = MulDiv(96, scale, 96), margin = MulDiv(16, scale, 96);
  const bool moved = abs(point.x - drag_origin.x) + abs(point.y - drag_origin.y) > MulDiv(16, scale, 96);
  // A near-transparent OLE probe checks the actual payload before revealing
  // the receiver. Mouse movement alone must never open the visible window.
  GUITHREADINFO gui{sizeof(gui)};
  const bool moving_window = GetGUIThreadInfo(0, &gui) && (gui.flags & GUI_INMOVESIZE);
  const bool sustained = GetTickCount64() - drag_started_at >= 180;
  SetProp(receiver_window, L"SuperClipboard.DragState", reinterpret_cast<HANDLE>(static_cast<INT_PTR>(
    static_cast<int>(down) | (moved << 1) | (sustained << 2) | (moving_window << 3) |
    (receiver_probe_checked << 4) | (receiver_file_drag << 5) | (desktop_origin_checked << 6))));
  if (moved && sustained && !moving_window && !desktop_origin_checked) {
    desktop_origin_checked = true;
    if (IsDesktopFileDragOrigin(drag_source_window, drag_origin)) {
      receiver_file_drag = true;
      receiver_probe_checked = true;
    }
  }
  if (receiver_probe) {
    if (moved && sustained && !moving_window && !receiver_probe_checked && !receiver_file_drag) {
      // Keep the probe stationary across the monitor. A tiny window following
      // the cursor misses OLE hit tests during fast Explorer/desktop drags.
      auto style = GetWindowLongPtr(receiver_probe, GWL_EXSTYLE);
      if (style & WS_EX_TRANSPARENT) SetWindowLongPtr(receiver_probe, GWL_EXSTYLE, style & ~WS_EX_TRANSPARENT);
      SetWindowPos(receiver_probe, HWND_TOPMOST, monitor.rcMonitor.left, monitor.rcMonitor.top,
        monitor.rcMonitor.right - monitor.rcMonitor.left,
        monitor.rcMonitor.bottom - monitor.rcMonitor.top, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    } else {
      // Let the OLE loop leave the probe naturally, without consuming a drop
      // or continuing to cover the desktop after inspecting the formats.
      if (receiver_probe_checked) {
        auto style = GetWindowLongPtr(receiver_probe, GWL_EXSTYLE);
        if (!(style & WS_EX_TRANSPARENT)) SetWindowLongPtr(receiver_probe, GWL_EXSTYLE, style | WS_EX_TRANSPARENT);
      }
      if (!receiver_probe_engaged) ShowWindow(receiver_probe, SW_HIDE);
    }
  }
  if (receiver_file_drag && !moving_window) {
    const bool visible = IsWindowVisible(receiver_window) != FALSE;
    SetWindowPos(receiver_window, HWND_TOPMOST, monitor.rcWork.left + margin,
      monitor.rcWork.top + margin, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    if (!visible) RedrawWindow(receiver_window, nullptr, nullptr, RDW_INVALIDATE | RDW_UPDATENOW);
  }
  else ShowWindow(receiver_window, SW_HIDE);
}
// Windows 11 stores the user's per-icon preference here. Set only this app's
// first-run default; a subsequent manual choice to hide it remains respected.
bool EnsureTrayVisibleByDefault() {
  wchar_t executable[32768]{};
  if (!GetModuleFileName(nullptr, executable, 32768)) return true;
  HKEY root = nullptr;
  if (RegOpenKeyEx(HKEY_CURRENT_USER, L"Control Panel\\NotifyIconSettings", 0,
      KEY_ENUMERATE_SUB_KEYS, &root) != ERROR_SUCCESS) return false;
  bool found = false;
  for (DWORD index = 0;; ++index) {
    wchar_t name[256]{}; DWORD name_size = 256;
    const auto status = RegEnumKeyEx(root, index, name, &name_size, nullptr, nullptr, nullptr, nullptr);
    if (status == ERROR_NO_MORE_ITEMS) break;
    if (status != ERROR_SUCCESS) continue;
    HKEY icon = nullptr;
    if (RegOpenKeyEx(root, name, 0, KEY_QUERY_VALUE | KEY_SET_VALUE, &icon) != ERROR_SUCCESS) continue;
    wchar_t path[32768]{}; DWORD path_bytes = sizeof(path);
    if (RegGetValue(icon, nullptr, L"ExecutablePath", RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ,
        nullptr, path, &path_bytes) == ERROR_SUCCESS && _wcsicmp(path, executable) == 0) {
      DWORD configured = 0, bytes = sizeof(configured);
      RegGetValue(icon, nullptr, L"SuperClipboardDefaultVisible", RRF_RT_REG_DWORD,
        nullptr, &configured, &bytes);
      if (configured == 1) found = true;
      else {
        DWORD visible = 1;
        if (RegSetValueEx(icon, L"IsPromoted", 0, REG_DWORD,
            reinterpret_cast<const BYTE*>(&visible), sizeof(visible)) == ERROR_SUCCESS) {
          found = RegSetValueEx(icon, L"SuperClipboardDefaultVisible", 0, REG_DWORD,
            reinterpret_cast<const BYTE*>(&visible), sizeof(visible)) == ERROR_SUCCESS;
        }
      }
    }
    RegCloseKey(icon);
  }
  RegCloseKey(root);
  return found;
}
HICON TrayThemeIcon() {
  DWORD light = 1, bytes = sizeof(light);
  RegGetValue(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
    L"SystemUsesLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &bytes);
  return LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(light ? IDI_TRAY_LIGHT : IDI_TRAY_DARK));
}
void TrayIcon(HWND hwnd) {
  tray = {}; tray.cbSize = sizeof(tray); tray.hWnd = hwnd; tray.uID = 1;
  tray.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP; tray.uCallbackMessage = kTray;
  tray.hIcon = TrayThemeIcon();
  wcscpy_s(tray.szTip, L"口袋Cube");
  Shell_NotifyIcon(NIM_ADD, &tray);
  tray_visibility_attempts = 0;
  SetTimer(hwnd, kTrayVisibility, 1000, nullptr);
}
}
class PlatformBridge::DropTarget : public IDropTarget {
 public:
  explicit DropTarget(PlatformBridge* owner, bool receiver = false, bool probe = false)
    : owner_(owner), receiver_(receiver), probe_(probe) {}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** out) override {
    if (iid == IID_IUnknown || iid == IID_IDropTarget) { *out = this; AddRef(); return S_OK; }
    *out = nullptr; return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override { auto n = --refs_; if (!n) delete this; return n; }
  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* object, DWORD, POINTL, DWORD* effect) override {
    accepted_ = false;
    for (auto cf : {static_cast<CLIPFORMAT>(CF_HDROP), static_cast<CLIPFORMAT>(CF_UNICODETEXT),
        static_cast<CLIPFORMAT>(CF_DIB), static_cast<CLIPFORMAT>(RegisterClipboardFormat(CFSTR_FILEDESCRIPTORW)), static_cast<CLIPFORMAT>(RegisterClipboardFormat(L"PNG"))}) {
      FORMATETC f{cf, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
      if ((!receiver_ || cf == CF_HDROP || cf == RegisterClipboardFormat(CFSTR_FILEDESCRIPTORW)) && SUCCEEDED(object->QueryGetData(&f))) accepted_ = true;
    }
    if (probe_) {
      receiver_probe_engaged = true;
      receiver_probe_checked = true;
      receiver_file_drag = accepted_;
      *effect = DROPEFFECT_NONE;
      // Defer window changes until the OLE callback has returned.
      PostMessage(receiver_window, kReceiverInput, 0, 0);
      return S_OK;
    }
    *effect &= accepted_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;
    if (receiver_) { receiver_targeted = accepted_; InvalidateRect(receiver_window, nullptr, FALSE); }
    owner_->Notify("dropHover", Value(accepted_)); return S_OK;
  }
  HRESULT STDMETHODCALLTYPE DragOver(DWORD, POINTL, DWORD* effect) override {
    *effect &= accepted_ && !probe_ ? DROPEFFECT_COPY : DROPEFFECT_NONE; return S_OK;
  }
  HRESULT STDMETHODCALLTYPE DragLeave() override {
    if (probe_) {
      receiver_probe_engaged = false;
      PostMessage(receiver_window, kReceiverInput, 0, 0);
      return S_OK;
    }
    if (receiver_) { receiver_targeted = false; InvalidateRect(receiver_window, nullptr, FALSE); }
    owner_->Notify("dropHover", Value(false)); return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Drop(IDataObject* object, DWORD, POINTL, DWORD* effect) override {
    // The probe only observes formats; it never reads or consumes a drop.
    if (probe_) {
      receiver_probe_engaged = false;
      PostMessage(receiver_window, kReceiverInput, 0, 0);
      *effect = DROPEFFECT_NONE; return S_OK;
    }
    owner_->Notify("dropHover", Value(false));
    if (receiver_) { receiver_targeted = false; ShowWindow(receiver_window, SW_HIDE); }
    Value data = accepted_ ? clipboard_native::Read(owner_->window_, object) : Value();
    if (std::holds_alternative<Map>(data)) {
      owner_->Notify("drop", data); *effect = DROPEFFECT_COPY;
    } else { *effect = DROPEFFECT_NONE; }
    return S_OK;
  }
 private:
  ULONG refs_ = 1; PlatformBridge* owner_; bool accepted_ = false, receiver_ = false, probe_ = false;
};

PlatformBridge::PlatformBridge(flutter::BinaryMessenger* messenger, HWND window,
    HWND view, const std::string& mode) : window_(window), view_(view), mode_(mode) {
  bridges[mode] = this;
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(messenger,
    "superclipboard/platform", &flutter::StandardMethodCodec::GetInstance());
  if (mode != "main") {
    SetWindowLongPtr(window_, GWL_EXSTYLE, (GetWindowLongPtr(window_, GWL_EXSTYLE) | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW);
    SetWindowLongPtr(window_, GWL_STYLE, WS_POPUP | WS_THICKFRAME | WS_CLIPCHILDREN |
      (mode == "transfer" ? WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU : 0));
    SetWindowPos(window_, mode == "transfer" ? HWND_TOPMOST : HWND_TOP, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED | SWP_NOACTIVATE);
  } else {
    TrayIcon(window_);
    WNDCLASS wc{}; wc.lpfnWndProc = ReceiverProc; wc.hInstance = GetModuleHandle(nullptr);
    wc.lpszClassName = L"SuperClipboard.DragReceiver"; wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    RegisterClass(&wc);
    // An independent top-level window stays available when all Flutter windows
    // are hidden or minimized. Keep its timer independent of their lifecycle.
    receiver_window = CreateWindowEx(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      wc.lpszClassName, L"口袋Cube 文件收纳", WS_POPUP, 0, 0, 190, 90, nullptr, nullptr, wc.hInstance, nullptr);
    if (receiver_window) {
      const DWM_WINDOW_CORNER_PREFERENCE round = DWMWCP_ROUND;
      DwmSetWindowAttribute(receiver_window, DWMWA_WINDOW_CORNER_PREFERENCE, &round, sizeof(round));
      auto target = new DropTarget(this, true);
      if (FAILED(RegisterDragDrop(receiver_window, target))) { DestroyWindow(receiver_window); receiver_window = nullptr; }
      target->Release();
      if (receiver_window) {
        WNDCLASS probe_class{};
        probe_class.lpfnWndProc = DefWindowProc;
        probe_class.hInstance = wc.hInstance;
        probe_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
        probe_class.lpszClassName = L"SuperClipboard.DragProbe";
        RegisterClass(&probe_class);
        receiver_probe = CreateWindowEx(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED,
          probe_class.lpszClassName, L"", WS_POPUP, 0, 0, 32, 32, nullptr, nullptr, wc.hInstance, nullptr);
        if (receiver_probe) {
          // Alpha zero is excluded from hit testing. Alpha one lets OLE inspect
          // the payload without displaying a visible collection window.
          SetLayeredWindowAttributes(receiver_probe, 0, 1, LWA_ALPHA);
          auto probe_target = new DropTarget(this, true, true);
          if (FAILED(RegisterDragDrop(receiver_probe, probe_target))) {
            DestroyWindow(receiver_probe); receiver_probe = nullptr;
          }
          probe_target->Release();
        }
        SetTimer(receiver_window, kReceiverPoll, 50, nullptr);
        receiver_mouse_hook = SetWindowsHookEx(WH_MOUSE_LL, ReceiverMouseProc, GetModuleHandle(nullptr), 0);
        SetProp(receiver_window, L"SuperClipboard.MouseHookInstalled", reinterpret_cast<HANDLE>(static_cast<INT_PTR>(receiver_mouse_hook != nullptr)));
        receiver_keyboard_hook = SetWindowsHookEx(WH_KEYBOARD_LL, ReceiverKeyboardProc, GetModuleHandle(nullptr), 0);
      }
    }
  }
  const DWM_WINDOW_CORNER_PREFERENCE corner = DWMWCP_ROUND;
  DwmSetWindowAttribute(window_, DWMWA_WINDOW_CORNER_PREFERENCE, &corner, sizeof(corner));
  const COLORREF no_border = 0xfffffffe;
  DwmSetWindowAttribute(window_, DWMWA_BORDER_COLOR, &no_border, sizeof(no_border));
  if (mode == "transfer") {
    drop_ = new DropTarget(this);
    RegisterDragDrop(window_, drop_); RegisterDragDrop(view_, drop_);
  }
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& method = call.method_name();
    const auto* args = call.arguments();
    const auto* map = args ? std::get_if<Map>(args) : nullptr;
    if (method == "broadcast") {
      if (args) shared_state = *args;
      for (auto& [mode, bridge] : bridges) if (mode != "main") bridge->Notify("state", shared_state);
      result->Success();
    } else if (method == "shortcutSettings") {
      auto main = bridges.find("main");
      if (main != bridges.end()) {
        main->second->ShowWindowForMode("main");
        main->second->Notify("shortcutSettings");
      }
      result->Success();
    } else if (method == "setShortcut" || method == "setShortcuts") {
      auto main = bridges.find("main");
      if (main == bridges.end() || !map) { result->Success(Value(false)); return; }
      bool ok = true;
      if (method == "setShortcut") {
        auto it = map->find(Value("shortcut"));
        const auto* value = it == map->end() ? nullptr : std::get_if<Map>(&it->second);
        ok = value && SetShortcut(main->second->window_, clipboard_native::String(*map, "mode") == "popover" ? kPopoverHotkey : kTransferHotkey, *value);
      } else {
        for (auto name : {"popover", "transfer"}) {
          auto it = map->find(Value(name));
          const auto* value = it == map->end() ? nullptr : std::get_if<Map>(&it->second);
          if (value && !SetShortcut(main->second->window_, std::string(name) == "popover" ? kPopoverHotkey : kTransferHotkey, *value)) ok = false;
        }
      }
      result->Success(Value(ok));
    } else if (method == "glassAppearance") {
      if (mode_ != "main") ConfigureGlass(map && Bool(*map, "dark"), map && Bool(*map, "opaque"));
      result->Success();
    } else if (method == "ready") {
      ready_ = true; result->Success(shared_state);
    } else if (method == "action") {
      auto main = bridges.find("main");
      if (main == bridges.end()) { result->Error("unavailable", "Main window unavailable"); return; }
      auto reply = std::shared_ptr<flutter::MethodResult<Value>>(std::move(result));
      main->second->channel_->InvokeMethod("action", std::make_unique<Value>(args ? *args : Value()),
        std::make_unique<flutter::MethodResultFunctions<Value>>(
          [reply](const Value* value) { reply->Success(value ? *value : Value(true)); },
          [reply](const std::string& code, const std::string& message, const Value*) { reply->Error(code, message); },
          [reply]() { reply->NotImplemented(); }));
    } else if (method == "listen") {
      if (map) clipboard_native::SetCache(clipboard_native::String(*map, "cache"));
      ready_ = true;
      if (!map || !map->count(Value("enabled")) || Bool(*map, "enabled")) AddClipboardFormatListener(window_);
      result->Success();
    } else if (method == "readClipboard") {
      auto value = clipboard_native::Read(window_);
      if (std::holds_alternative<std::monostate>(value) && clipboard_retries++ < 5) SetTimer(window_, kClipboardRetry, 70, nullptr);
      else clipboard_retries = 0;
      result->Success(value);
    } else if (method == "writeClipboard") {
      result->Success(Value(map && clipboard_native::Write(window_, *map)));
    } else if (method == "show") {
      if (args && std::holds_alternative<std::string>(*args)) ShowWindowForMode(std::get<std::string>(*args));
      result->Success();
    } else if (method == "setWindowStyle") {
      windows_style_ = !args || !std::holds_alternative<std::string>(*args) || std::get<std::string>(*args) != "mac";
      if (!windows_style_ && mode_ != "popover") {
        if (IsZoomed(window_)) ShowWindow(window_, SW_RESTORE);
        RECT rect; GetWindowRect(window_, &rect);
        const int width = static_cast<int>((mode_ == "main" ? 460 : 390) * GetDpiForWindow(window_) / 96.0);
        if (rect.right - rect.left > width) SetWindowPos(window_, nullptr, 0, 0, width, rect.bottom - rect.top, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
      }
      result->Success(Value(IsZoomed(window_) != FALSE));
    } else if (method == "windowMenu") {
      POINT cursor; GetCursorPos(&cursor);
      HMENU menu = GetSystemMenu(window_, FALSE);
      const bool zoomed = IsZoomed(window_) != FALSE;
      EnableMenuItem(menu, SC_RESTORE, MF_BYCOMMAND | (zoomed ? MF_ENABLED : MF_GRAYED));
      EnableMenuItem(menu, SC_MAXIMIZE, MF_BYCOMMAND | (zoomed ? MF_GRAYED : MF_ENABLED));
      const auto command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, cursor.x, cursor.y, 0, window_, nullptr);
      if (command) PostMessage(window_, WM_SYSCOMMAND, command, 0);
      result->Success();
    } else if (method == "windowAction") {
      if (args && std::holds_alternative<std::string>(*args)) {
        const auto action = std::get<std::string>(*args);
        if (action == "close") Hide();
        else if (action == "minimize") ShowWindow(window_, SW_MINIMIZE);
        else if (action == "zoom") ShowWindow(window_, IsZoomed(window_) ? SW_RESTORE : SW_MAXIMIZE);
      }
      result->Success();
    } else if (method == "hide") {
      Hide(); result->Success();
    } else if (method == "dragWindow") {
      ReleaseCapture(); SendMessage(window_, WM_NCLBUTTONDOWN, HTCAPTION, 0); result->Success();
    } else if (method == "quit") {
      quitting = true; result->Success(); PostQuitMessage(0);
    } else if (method == "thumbnail") {
      result->Success(Value(map ? clipboard_native::Thumbnail(clipboard_native::String(*map, "path")) : ""));
    } else if (method == "startDrag") {
      if (map) {
        exporting_drag = true;
        if (receiver_window) ShowWindow(receiver_window, SW_HIDE);
        clipboard_native::Drag(window_, *map);
        exporting_drag = false; Notify("dropHover", Value(false));
      }
      result->Success();
    } else if (method == "reveal" || method == "openFolder") {
      if (args && std::holds_alternative<std::string>(*args)) {
        auto path = clipboard_native::Wide(std::get<std::string>(*args));
        std::replace(path.begin(), path.end(), L'/', L'\\');
        if (method == "reveal") {
          PIDLIST_ABSOLUTE item = nullptr;
          if (SUCCEEDED(SHParseDisplayName(path.c_str(), nullptr, &item, 0, nullptr))) {
            SHOpenFolderAndSelectItems(item, 0, nullptr, 0); CoTaskMemFree(item);
          }
        } else ShellExecute(window_, L"open", path.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
      }
      result->Success();
    } else if (method == "chooseFolder") {
      IFileDialog* dialog = nullptr; std::string chosen;
      if (SUCCEEDED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) {
        DWORD options; dialog->GetOptions(&options); dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
        if (SUCCEEDED(dialog->Show(window_))) {
          IShellItem* item = nullptr;
          if (SUCCEEDED(dialog->GetResult(&item))) {
            PWSTR path = nullptr;
            if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) { chosen = clipboard_native::Utf8(path); CoTaskMemFree(path); }
            item->Release();
          }
        }
        dialog->Release();
      }
      result->Success(Value(chosen));
    } else if (method == "startup") {
      HKEY key = nullptr; bool enabled = false;
      if (RegCreateKeyEx(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
          nullptr, 0, KEY_QUERY_VALUE | KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
        result->Error("registry", "Unable to change startup setting"); return;
      }
      // First launch registers by default. Later launches respect the saved user setting.
      if (map && map->count(Value("enabled")) && !std::holds_alternative<std::monostate>(map->at(Value("enabled")))) {
        if (Bool(*map, "enabled")) {
          wchar_t exe[32768]; GetModuleFileName(nullptr, exe, 32768);
          auto value = L"\"" + std::wstring(exe) + L"\" --background";
          auto status = RegSetValueEx(key, L"SuperClipboard", 0, REG_SZ,
            reinterpret_cast<const BYTE*>(value.c_str()), static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
          if (status != ERROR_SUCCESS) { RegCloseKey(key); result->Error("registry", "Unable to register startup"); return; }
        } else { RegDeleteValue(key, L"SuperClipboard"); }
      }
      enabled = RegQueryValueEx(key, L"SuperClipboard", nullptr, nullptr, nullptr, nullptr) == ERROR_SUCCESS;
      RegCloseKey(key); result->Success(Value(enabled));
    } else result->NotImplemented();
  });
}
PlatformBridge::~PlatformBridge() {
  bridges.erase(mode_);
  if (mode_ == "main") {
    UnregisterHotKey(window_, kPopoverHotkey); UnregisterHotKey(window_, kTransferHotkey);
    if (receiver_mouse_hook) { UnhookWindowsHookEx(receiver_mouse_hook); receiver_mouse_hook = nullptr; }
    if (receiver_keyboard_hook) { UnhookWindowsHookEx(receiver_keyboard_hook); receiver_keyboard_hook = nullptr; }
    if (receiver_window) KillTimer(receiver_window, kReceiverPoll);
    if (receiver_probe) { RevokeDragDrop(receiver_probe); DestroyWindow(receiver_probe); receiver_probe = nullptr; }
    if (receiver_window) { RevokeDragDrop(receiver_window); DestroyWindow(receiver_window); receiver_window = nullptr; }
    RemoveClipboardFormatListener(window_); Shell_NotifyIcon(NIM_DELETE, &tray); }
  if (drop_) { RevokeDragDrop(view_); RevokeDragDrop(window_); drop_->Release(); }
}
void PlatformBridge::ConfigureGlass(bool dark, bool opaque) {
  BOOL immersive_dark = dark;
  DwmSetWindowAttribute(window_, DWMWA_USE_IMMERSIVE_DARK_MODE, &immersive_dark, sizeof(immersive_dark));
  // DWM must preserve the child surface alpha as well as the top-level surface.
  HRGN region = CreateRectRgn(0, 0, -1, -1);
  DWM_BLURBEHIND blur{};
  blur.dwFlags = DWM_BB_ENABLE | DWM_BB_BLURREGION;
  blur.fEnable = !opaque;
  blur.hRgnBlur = region;
  DwmEnableBlurBehindWindow(window_, &blur);
  DwmEnableBlurBehindWindow(view_, &blur);
  DeleteObject(region);
  // Request acrylic consistently; never fall back to a sharp see-through
  // desktop. The OS may use a solid material when transparency is disabled.
  struct Accent { int state; DWORD flags, tint, animation; };
  struct Composition { int attribute; void* data; SIZE_T size; };
  using SetComposition = BOOL(WINAPI*)(HWND, Composition*);
  auto user32 = GetModuleHandle(L"user32.dll");
  auto set_composition = reinterpret_cast<SetComposition>(GetProcAddress(user32, "SetWindowCompositionAttribute"));
  const DWM_SYSTEMBACKDROP_TYPE none = DWMSBT_NONE;
  DwmSetWindowAttribute(window_, DWMWA_SYSTEMBACKDROP_TYPE, &none, sizeof(none));
  MARGINS margins{0, 0, 1, 0};
  DwmExtendFrameIntoClientArea(window_, &margins);
  if (set_composition) {
    Accent accent{opaque ? 0 : 4, 2, dark ? 0x3028201cUL : 0x30ffffffUL, 0};
    Composition composition{19, &accent, sizeof(accent)};
    set_composition(window_, &composition);
  }
}
void PlatformBridge::Notify(const std::string& method, const Value& value) {
  channel_->InvokeMethod(method, std::make_unique<Value>(value));
}
void PlatformBridge::Hide() {
  Notify("dropHover", Value(false));
  ShowWindow(window_, SW_HIDE);
  if (mode_ == "transfer" && bridges.count("main")) bridges["main"]->Notify("transferVisibility", Value(false));
}
void PlatformBridge::ShowWindowForMode(const std::string& mode) {
  if (mode != "main" && mode != "popover" && mode != "transfer") return;
  if (mode == "main" && mode_ == "popover") Hide();
  if (!bridges.count(mode)) {
    flutter::DartProject project(L"data"); project.set_dart_entrypoint_arguments({mode});
    auto window = std::make_unique<FlutterWindow>(project, mode);
    POINT cursor; GetCursorPos(&cursor);
    window->Create(mode == "transfer" ? L"悬浮中转" : L"口袋Cube 快捷历史",
      Win32Window::Point(200, 100), Win32Window::Size(mode == "transfer" ? 350 : 390, 520));
    extra_windows.push_back(std::move(window));
  }
  auto bridge = bridges[mode]; auto hwnd = bridge->window_;
  if (mode == "popover") {
    POINT cursor; GetCursorPos(&cursor); MONITORINFO info{sizeof(info)};
    GetMonitorInfo(MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST), &info);
    const double scale = GetDpiForWindow(hwnd) / 96.0;
    const int w = static_cast<int>(390 * scale), h = static_cast<int>(520 * scale);
    const int x = std::clamp(static_cast<int>(cursor.x - w / 2), static_cast<int>(info.rcWork.left), static_cast<int>(info.rcWork.right - w));
    const int y = std::clamp(static_cast<int>(cursor.y - h - 10), static_cast<int>(info.rcWork.top), static_cast<int>(info.rcWork.bottom - h));
    SetWindowPos(hwnd, HWND_TOPMOST, x, y, w, h, SWP_SHOWWINDOW);
  } else if (mode == "transfer") {
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    if (bridges.count("main")) bridges["main"]->Notify("transferVisibility", Value(true));
  }
  ShowWindow(hwnd, SW_RESTORE); SetForegroundWindow(hwnd);
  bridge->Notify("shown");
}
std::optional<LRESULT> PlatformBridge::Handle(UINT message, WPARAM wp, LPARAM lp) {
  if (message == show_main && mode_ == "main") { ShowWindowForMode("main"); return 0; }
  if (message == taskbar_created && mode_ == "main") { TrayIcon(window_); return 0; }
  switch (message) {
    case WM_SETTINGCHANGE:
      if (mode_ == "main") { tray.hIcon = TrayThemeIcon(); Shell_NotifyIcon(NIM_MODIFY, &tray); }
      break;
    case WM_CLOSE:
      if (!quitting) { Hide(); return 0; } break;
    case WM_CLIPBOARDUPDATE:
      if (ready_ && mode_ == "main" && !clipboard_native::IsOwnClipboard()) {
        const DWORD sequence = GetClipboardSequenceNumber();
        if (sequence != observed_sequence) { observed_sequence = sequence; Notify("clipboardChanged"); }
      }
      return 0;
    case WM_HOTKEY:
      if (mode_ == "main" && (wp == kPopoverHotkey || wp == kTransferHotkey)) {
        const std::string mode = wp == kPopoverHotkey ? "popover" : "transfer";
        if (bridges.count(mode) && IsWindowVisible(bridges[mode]->window_)) bridges[mode]->Hide();
        else ShowWindowForMode(mode);
        return 0;
      }
      break;
    case WM_TIMER:
      if (wp == kTrayVisibility) {
        if (EnsureTrayVisibleByDefault() || ++tray_visibility_attempts >= 10) KillTimer(window_, kTrayVisibility);
        return 0;
      }
      if (wp == kClipboardRetry) { KillTimer(window_, kClipboardRetry); Notify("clipboardChanged"); return 0; }
      break;
    case WM_ACTIVATE:
      if (ready_) Notify("windowFocus", Value(LOWORD(wp) != WA_INACTIVE));
      if (mode_ == "popover" && LOWORD(wp) == WA_INACTIVE) Hide();
      break;
    case WM_SIZE:
      if (ready_ && wp != SIZE_MINIMIZED) Notify("windowState", Value(IsZoomed(window_) != FALSE));
      break;
    case WM_GETMINMAXINFO: {
      auto info = reinterpret_cast<MINMAXINFO*>(lp);
      const double scale = GetDpiForWindow(window_) / 96.0;
      info->ptMinTrackSize = {static_cast<LONG>((mode_ == "transfer" ? 320 : mode_ == "popover" ? 390 : 420) * scale), static_cast<LONG>((mode_ == "transfer" ? 360 : mode_ == "popover" ? 520 : 440) * scale)};
      if (mode_ == "popover") {
        info->ptMaxSize.x = info->ptMaxTrackSize.x = static_cast<LONG>(390 * scale);
        info->ptMaxSize.y = info->ptMaxTrackSize.y = static_cast<LONG>(520 * scale);
      } else if (!windows_style_) {
        info->ptMaxSize.x = info->ptMaxTrackSize.x = static_cast<LONG>((mode_ == "main" ? 460 : 390) * scale);
      } else {
        MONITORINFO monitor{sizeof(monitor)};
        if (GetMonitorInfo(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST), &monitor)) {
          info->ptMaxPosition = {monitor.rcWork.left - monitor.rcMonitor.left, monitor.rcWork.top - monitor.rcMonitor.top};
          info->ptMaxSize = {monitor.rcWork.right - monitor.rcWork.left, monitor.rcWork.bottom - monitor.rcWork.top};
        }
      }
      return 0;
    }
    case WM_NCCALCSIZE:
      if (wp) return 0;
      break;
    case kTray:
      if (lp == WM_LBUTTONUP) {
        if (bridges.count("popover") && IsWindowVisible(bridges["popover"]->window_)) bridges["popover"]->Hide();
        else ShowWindowForMode("popover");
      } else if (lp == WM_LBUTTONDBLCLK) ShowWindowForMode("main");
      else if (lp == WM_RBUTTONUP) {
        HMENU menu = CreatePopupMenu();
        AppendMenu(menu, MF_STRING, 1, L"打开主窗口"); AppendMenu(menu, MF_STRING, 2, L"悬浮中转");
        AppendMenu(menu, MF_SEPARATOR, 0, nullptr); AppendMenu(menu, MF_STRING, 3, L"退出 口袋Cube…");
        POINT p; GetCursorPos(&p); SetForegroundWindow(window_);
        auto cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, p.x, p.y, 0, window_, nullptr);
        DestroyMenu(menu);
        if (cmd == 1) ShowWindowForMode("main"); else if (cmd == 2) ShowWindowForMode("transfer");
        else if (cmd == 3 && MessageBox(window_, L"退出后将停止记录剪贴板内容。", L"退出 口袋Cube？", MB_OKCANCEL | MB_ICONQUESTION) == IDOK) {
          quitting = true; PostQuitMessage(0);
        }
      }
      return 0;
  }
  return std::nullopt;
}
