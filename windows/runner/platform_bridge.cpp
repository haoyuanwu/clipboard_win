#include "platform_bridge.h"
#include "clipboard_native.h"
#include "flutter_window.h"
#include "resource.h"
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
void TrayIcon(HWND hwnd) {
  tray = {}; tray.cbSize = sizeof(tray); tray.hWnd = hwnd; tray.uID = 1;
  tray.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP; tray.uCallbackMessage = kTray;
  tray.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray.szTip, L"SuperClipboard");
  Shell_NotifyIcon(NIM_ADD, &tray);
  tray_visibility_attempts = 0;
  SetTimer(hwnd, kTrayVisibility, 1000, nullptr);
}
}
class PlatformBridge::DropTarget : public IDropTarget {
 public:
  explicit DropTarget(PlatformBridge* owner) : owner_(owner) {}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** out) override {
    if (iid == IID_IUnknown || iid == IID_IDropTarget) { *out = this; AddRef(); return S_OK; }
    *out = nullptr; return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override { auto n = --refs_; if (!n) delete this; return n; }
  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* object, DWORD, POINTL, DWORD* effect) override {
    accepted_ = false;
    for (auto cf : {static_cast<CLIPFORMAT>(CF_HDROP), static_cast<CLIPFORMAT>(CF_UNICODETEXT),
        static_cast<CLIPFORMAT>(CF_DIB), static_cast<CLIPFORMAT>(RegisterClipboardFormat(L"PNG"))}) {
      FORMATETC f{cf, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
      if (SUCCEEDED(object->QueryGetData(&f))) accepted_ = true;
    }
    *effect = accepted_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;
    owner_->Notify("dropHover", Value(accepted_)); return S_OK;
  }
  HRESULT STDMETHODCALLTYPE DragOver(DWORD, POINTL, DWORD* effect) override {
    *effect = accepted_ ? DROPEFFECT_COPY : DROPEFFECT_NONE; return S_OK;
  }
  HRESULT STDMETHODCALLTYPE DragLeave() override { owner_->Notify("dropHover", Value(false)); return S_OK; }
  HRESULT STDMETHODCALLTYPE Drop(IDataObject* object, DWORD, POINTL, DWORD* effect) override {
    owner_->Notify("dropHover", Value(false));
    Value data = clipboard_native::Read(owner_->window_, object);
    if (std::holds_alternative<Map>(data)) {
      owner_->Notify("drop", data); *effect = DROPEFFECT_COPY;
    } else { *effect = DROPEFFECT_NONE; }
    return S_OK;
  }
 private:
  ULONG refs_ = 1; PlatformBridge* owner_; bool accepted_ = false;
};

PlatformBridge::PlatformBridge(flutter::BinaryMessenger* messenger, HWND window,
    HWND view, const std::string& mode) : window_(window), view_(view), mode_(mode) {
  bridges[mode] = this;
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(messenger,
    "superclipboard/platform", &flutter::StandardMethodCodec::GetInstance());
  if (mode != "main") {
    SetWindowLongPtr(window_, GWL_EXSTYLE, (GetWindowLongPtr(window_, GWL_EXSTYLE) | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW);
    SetWindowLongPtr(window_, GWL_STYLE, WS_POPUP | WS_THICKFRAME | WS_CLIPCHILDREN);
    SetWindowPos(window_, mode == "transfer" ? HWND_TOPMOST : HWND_TOP, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED | SWP_NOACTIVATE);
  } else {
    TrayIcon(window_);
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
      if (map) clipboard_native::Drag(window_, *map);
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
  if (mode_ == "main") { RemoveClipboardFormatListener(window_); Shell_NotifyIcon(NIM_DELETE, &tray); }
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
    window->Create(mode == "transfer" ? L"悬浮中转" : L"SuperClipboard 快捷历史",
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
    case WM_CLOSE:
      if (!quitting) { Hide(); return 0; } break;
    case WM_CLIPBOARDUPDATE:
      if (ready_ && mode_ == "main" && !clipboard_native::IsOwnClipboard()) {
        const DWORD sequence = GetClipboardSequenceNumber();
        if (sequence != observed_sequence) { observed_sequence = sequence; Notify("clipboardChanged"); }
      }
      return 0;
    case WM_TIMER:
      if (wp == kTrayVisibility) {
        if (EnsureTrayVisibleByDefault() || ++tray_visibility_attempts >= 10) KillTimer(window_, kTrayVisibility);
        return 0;
      }
      if (wp == kClipboardRetry) { KillTimer(window_, kClipboardRetry); Notify("clipboardChanged"); return 0; }
      break;
    case WM_ACTIVATE:
      if (mode_ == "popover" && LOWORD(wp) == WA_INACTIVE) Hide();
      break;
    case WM_GETMINMAXINFO: {
      auto info = reinterpret_cast<MINMAXINFO*>(lp);
      double scale = GetDpiForWindow(window_) / 96.0;
      info->ptMinTrackSize = {static_cast<LONG>((mode_ == "transfer" ? 320 : mode_ == "popover" ? 390 : 420) * scale), static_cast<LONG>((mode_ == "transfer" ? 360 : mode_ == "popover" ? 520 : 440) * scale)};
      info->ptMaxTrackSize.x = static_cast<LONG>((mode_ == "main" ? 460 : 390) * scale);
      info->ptMaxSize.x = info->ptMaxTrackSize.x;
      if (mode_ == "popover") info->ptMaxSize.y = info->ptMaxTrackSize.y = static_cast<LONG>(520 * scale);
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
        AppendMenu(menu, MF_SEPARATOR, 0, nullptr); AppendMenu(menu, MF_STRING, 3, L"退出 SuperClipboard…");
        POINT p; GetCursorPos(&p); SetForegroundWindow(window_);
        auto cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, p.x, p.y, 0, window_, nullptr);
        DestroyMenu(menu);
        if (cmd == 1) ShowWindowForMode("main"); else if (cmd == 2) ShowWindowForMode("transfer");
        else if (cmd == 3 && MessageBox(window_, L"退出后将停止记录剪贴板内容。", L"退出 SuperClipboard？", MB_OKCANCEL | MB_ICONQUESTION) == IDOK) {
          quitting = true; PostQuitMessage(0);
        }
      }
      return 0;
  }
  return std::nullopt;
}
