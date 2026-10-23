#include <windows.h>
#include <oleidl.h>
#include <shellapi.h>
#include <shlobj.h>
#include <string>
#include <exdisp.h>
#include <shldisp.h>
#include <shlguid.h>
#include <servprov.h>
#include <wrl/client.h>
#include <oleacc.h>
#include "desktop_drag_source.h"
#include <shlobj.h>
#include <string>
#include <filesystem>
#include <iostream>
#include <thread>
#include <vector>
#include <fstream>

// Exercise the real cross-process OLE path rather than invoking DragEnter directly.
class Payload : public IDataObject, public IDropSource {
 public:
  Payload(CLIPFORMAT format, const std::wstring& path) : format_(format), path_(path) {}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void** out) override {
    *out = nullptr;
    if (id == IID_IUnknown || id == IID_IDataObject) *out = static_cast<IDataObject*>(this);
    if (id == IID_IDropSource) *out = static_cast<IDropSource*>(this);
    if (!*out) return E_NOINTERFACE;
    AddRef(); return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override { auto n = --refs_; if (!n) delete this; return n; }
  HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC* f) override {
    return f && f->cfFormat == format_ && (f->tymed & TYMED_HGLOBAL) ? S_OK : DV_E_FORMATETC;
  }
  HRESULT STDMETHODCALLTYPE GetData(FORMATETC* f, STGMEDIUM* m) override {
    if (FAILED(QueryGetData(f))) return DV_E_FORMATETC;
    *m = {}; m->tymed = TYMED_HGLOBAL;
    m->hGlobal = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT,
      sizeof(DROPFILES) + (path_.size() + 2) * sizeof(wchar_t) + 128);
    auto p = static_cast<char*>(GlobalLock(m->hGlobal));
    if (format_ == CF_HDROP) {
      auto drop = reinterpret_cast<DROPFILES*>(p);
      drop->pFiles = sizeof(DROPFILES); drop->fWide = TRUE;
      lstrcpyW(reinterpret_cast<wchar_t*>(p + sizeof(DROPFILES)), path_.c_str());
    } else lstrcpyW(reinterpret_cast<wchar_t*>(p), L"ordinary dragged text");
    GlobalUnlock(m->hGlobal); return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC*, STGMEDIUM*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC*, FORMATETC*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE SetData(FORMATETC*, STGMEDIUM*, BOOL) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD direction, IEnumFORMATETC** out) override {
    if (direction != DATADIR_GET) return E_NOTIMPL;
    FORMATETC format{format_, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    return SHCreateStdEnumFmtEtc(1, &format, out);
  }
  HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC*, DWORD, IAdviseSink*, DWORD*) override { return OLE_E_ADVISENOTSUPPORTED; }
  HRESULT STDMETHODCALLTYPE DUnadvise(DWORD) override { return OLE_E_ADVISENOTSUPPORTED; }
  HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA**) override { return OLE_E_ADVISENOTSUPPORTED; }
  HRESULT STDMETHODCALLTYPE QueryContinueDrag(BOOL escape, DWORD keys) override {
    if (escape) return DRAGDROP_S_CANCEL;
    return keys & MK_LBUTTON ? S_OK : DRAGDROP_S_DROP;
  }
  HRESULT STDMETHODCALLTYPE GiveFeedback(DWORD) override { return DRAGDROP_S_USEDEFAULTCURSORS; }
 private:
  ULONG refs_ = 1;
  CLIPFORMAT format_;
  std::wstring path_;
};
struct Search { DWORD process; HWND receiver = nullptr; HWND main = nullptr; HWND probe = nullptr; HWND transfer = nullptr; };
BOOL CALLBACK Find(HWND h, LPARAM arg) {
  auto s = reinterpret_cast<Search*>(arg);
  DWORD process; GetWindowThreadProcessId(h, &process);
  if (process != s->process) return TRUE;
  wchar_t cls[256]{}; GetClassNameW(h, cls, 256);
  if (!wcscmp(cls, L"SuperClipboard.DragReceiver")) s->receiver = h;
  if (!wcscmp(cls, L"SuperClipboard.DragProbe")) s->probe = h;
  if (!wcscmp(cls, L"FLUTTER_RUNNER_WIN32_WINDOW")) s->main = h;
  wchar_t title[128]{}; GetWindowTextW(h, title, 128);
  if (!wcscmp(title, L"悬浮中转")) s->transfer = h;
  return TRUE;
}
bool DesktopDrag(HWND receiver, bool origin_only) {
  const auto wait = [](DWORD milliseconds) {
    const auto until = GetTickCount64() + milliseconds;
    do {
      MSG message;
      while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
        TranslateMessage(&message); DispatchMessageW(&message);
      }
      Sleep(10);
    } while (GetTickCount64() < until);
  };
  std::cout << "desktop test starting" << std::endl;
  HANDLE token = nullptr;
  if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    std::cout << "test restricted token=" << IsTokenRestricted(token) << std::endl;
    DWORD size = 0; GetTokenInformation(token, TokenIntegrityLevel, nullptr, 0, &size);
    std::vector<BYTE> bytes(size);
    if (GetTokenInformation(token, TokenIntegrityLevel, bytes.data(), size, &size)) {
      auto label = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(bytes.data());
      const auto count = *GetSidSubAuthorityCount(label->Label.Sid);
      std::cout << "test integrity=" << *GetSidSubAuthority(label->Label.Sid, count - 1) << std::endl;
    }
    CloseHandle(token);
  }
  using Microsoft::WRL::ComPtr;
  ComPtr<IShellWindows> windows;
  if (FAILED(CoCreateInstance(CLSID_ShellWindows, nullptr, CLSCTX_LOCAL_SERVER, IID_PPV_ARGS(&windows)))) { std::cout << "ShellWindows unavailable" << std::endl; return false; }
  VARIANT location{}; location.vt = VT_I4; location.lVal = CSIDL_DESKTOP;
  VARIANT root{}; long desktop_handle = 0; ComPtr<IDispatch> dispatch;
  if (FAILED(windows->FindWindowSW(&location, &root, SWC_DESKTOP, &desktop_handle, SWFO_NEEDDISPATCH, &dispatch))) { std::cout << "desktop dispatch unavailable" << std::endl; return false; }
  ComPtr<IServiceProvider> provider; ComPtr<IShellBrowser> browser; ComPtr<IShellView> view;
  ComPtr<IFolderView> folder_view; ComPtr<IShellFolder> folder;
  if (FAILED(dispatch.As(&provider)) || FAILED(provider->QueryService(SID_STopLevelBrowser, IID_PPV_ARGS(&browser))) ||
      FAILED(browser->QueryActiveShellView(&view)) || FAILED(view.As(&folder_view)) ||
      FAILED(folder_view->GetFolder(IID_PPV_ARGS(&folder)))) { std::cout << "desktop folder view unavailable" << std::endl; return false; }
  PWSTR desktop_path = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_Desktop, 0, nullptr, &desktop_path))) return false;
  const auto fixture = std::filesystem::path(desktop_path) /
    (L"Clipboard-drag-test-" + std::to_wstring(GetCurrentProcessId()) + L".txt");
  CoTaskMemFree(desktop_path);
  HANDLE file = CreateFileW(fixture.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  CloseHandle(file);
  SHChangeNotify(SHCNE_CREATE, SHCNF_PATHW | SHCNF_FLUSH, fixture.c_str(), nullptr);
  PIDLIST_RELATIVE item = nullptr; POINT position{};
  std::wstring name = fixture.filename().wstring();
  bool found = false;
  for (int i = 0; i < 30 && !found; ++i) {
    if (item) { CoTaskMemFree(item); item = nullptr; }
    if (SUCCEEDED(folder->ParseDisplayName(nullptr, nullptr, name.data(), nullptr, &item, nullptr)) &&
        SUCCEEDED(folder_view->GetItemPosition(item, &position))) found = true;
    else wait(100);
  }
  ComPtr<IShellDispatch> shell;
  CoCreateInstance(CLSID_Shell, nullptr, CLSCTX_ALL, IID_PPV_ARGS(&shell));
  bool visible = false;
  std::cout << "desktop item found=" << found << " shell=" << (shell != nullptr) << std::endl;
  if (found && shell) {
    shell->MinimizeAll(); wait(600);
    HWND view_window = nullptr; view->GetWindow(&view_window);
    HWND list = FindWindowExW(view_window, nullptr, L"SysListView32", nullptr);
    std::cout << "desktop list=" << list << " position=" << position.x << "," << position.y << std::endl;
    if (list) {
      view->SelectItem(item, SVSI_SELECT | SVSI_DESELECTOTHERS | SVSI_FOCUSED | SVSI_ENSUREVISIBLE);
      POINT spacing{}; folder_view->GetSpacing(&spacing);
      position.x += spacing.x / 2; position.y += 20;
      ClientToScreen(list, &position);
      ComPtr<IAccessible> accessible;
      if (SUCCEEDED(AccessibleObjectFromWindow(list, OBJID_CLIENT, IID_PPV_ARGS(&accessible)))) {
        long count = 0; accessible->get_accChildCount(&count);
        for (long index = 1; index <= count; ++index) {
          VARIANT child{}; child.vt = VT_I4; child.lVal = index;
          BSTR label = nullptr;
          if (SUCCEEDED(accessible->get_accName(child, &label)) && label) {
            const bool match = std::wstring(label).find(L"Clipboard-drag-test-" + std::to_wstring(GetCurrentProcessId())) == 0;
            SysFreeString(label);
            if (match) {
              long x, y, width, height;
              if (SUCCEEDED(accessible->accLocation(&x, &y, &width, &height, child))) {
                position = {x + width / 2, y + height / 3};
                std::cout << "accessible icon=" << x << "," << y << "," << width << "," << height << std::endl;
              }
              break;
            }
          }
        }
      }
      RECT list_rect{}; GetWindowRect(list, &list_rect);
      std::cout << "screen source=" << position.x << "," << position.y << " list bounds=" << list_rect.left << "," << list_rect.top << "," << list_rect.right << "," << list_rect.bottom << " spacing=" << spacing.x << "," << spacing.y << std::endl;
      SetForegroundWindow(GetAncestor(list, GA_ROOT));
      SetCursorPos(position.x, position.y); wait(100);
      wchar_t hit_class[256]{};
      GetClassNameW(WindowFromPoint(position), hit_class, 256);
      std::wcout << L"desktop initial hit=" << hit_class << std::endl;
      const bool file_origin = IsDesktopFileDragOrigin(list, position);
      const POINT blank{list_rect.right - 10, list_rect.top + 10};
      const bool blank_origin = IsDesktopFileDragOrigin(list, blank);
      std::cout << "desktop file origin=" << file_origin << " blank origin=" << blank_origin << std::endl;
      if (origin_only) {
        visible = file_origin && !blank_origin;
      } else {
      INPUT button{}; button.type = INPUT_MOUSE; button.mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
      SetLastError(0);
      auto sent = SendInput(1, &button, sizeof(button));
      std::cout << "desktop SendInput=" << sent << " error=" << GetLastError() << std::endl;
      wait(100);
      std::cout << "desktop button after down=" << (GetAsyncKeyState(VK_LBUTTON) & 0x8000) << std::endl;
      for (int i = 1; i <= 25; ++i) {
        SetCursorPos(position.x + 8 * i, position.y + 3 * i); wait(25);
      }
      wait(250);
      visible = IsWindowVisible(receiver) != FALSE;
      std::cout << "desktop button while moving=" << (GetAsyncKeyState(VK_LBUTTON) & 0x8000) << std::endl;
      int selected = 0; folder_view->ItemCount(SVGIO_SELECTION, &selected);
      GUITHREADINFO gui{sizeof(gui)}; GetGUIThreadInfo(0, &gui);
      wchar_t capture_class[256]{}; GetClassNameW(gui.hwndCapture, capture_class, 256);
      POINT current; GetCursorPos(&current); GetClassNameW(WindowFromPoint(current), hit_class, 256);
      std::wcout << L"desktop drag hit=" << hit_class << L" flags=" << gui.flags << L" selected=" << selected << std::endl;
      std::wcout << L"desktop capture=" << capture_class << std::endl;
      std::cout << "actual desktop file visible=" << visible << std::endl;
      std::cout << "hook presses=" << reinterpret_cast<ULONG_PTR>(GetPropW(receiver, L"SuperClipboard.MousePressCount")) << " state=" << reinterpret_cast<INT_PTR>(GetPropW(receiver, L"SuperClipboard.DragState")) << std::endl;
      // Cancel while still holding the button; never drop a fixture on the desktop.
      keybd_event(VK_ESCAPE, 0, 0, 0); wait(100);
      keybd_event(VK_ESCAPE, 0, KEYEVENTF_KEYUP, 0);
      mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0); wait(150);
      visible = visible && !IsWindowVisible(receiver);
      }
    }
    shell->UndoMinimizeALL();
  }
  if (item) CoTaskMemFree(item);
  DeleteFileW(fixture.c_str());
  SHChangeNotify(SHCNE_DELETE, SHCNF_PATHW | SHCNF_FLUSH, fixture.c_str(), nullptr);
  return visible;
}
int wmain(int argc, wchar_t** argv) {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  if ((argc != 2 && argc != 3) || FAILED(OleInitialize(nullptr))) return 2;
  const auto exe = std::filesystem::absolute(argv[1]);
  const auto data = std::filesystem::temp_directory_path() /
    (L"receiver-test-" + std::to_wstring(GetCurrentProcessId()));
  const auto fixture = data / L"empty-drag-folder";
  std::filesystem::create_directories(fixture);
  std::ofstream(fixture / L"one.txt") << "one";
  std::wstring args = L"\"" + exe.wstring() + L"\" --preview-instance --no-capture --no-startup --background --data-dir \"" + data.wstring() + L"\"";
  STARTUPINFOW startup{sizeof(startup)}; PROCESS_INFORMATION process{};
  if (!CreateProcessW(nullptr, args.data(), nullptr, nullptr, FALSE, 0, nullptr,
      exe.parent_path().c_str(), &startup, &process)) return 3;
  Search search{process.dwProcessId};
  for (int i = 0; i < 80 && !search.receiver; ++i) { Sleep(100); EnumWindows(Find, reinterpret_cast<LPARAM>(&search)); }
  POINT original; GetCursorPos(&original);
  auto helper = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
    L"STATIC", L"Drag trigger regression test", WS_POPUP | WS_VISIBLE,
    600, 400, 400, 250, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  bool passed = search.receiver && !IsWindowVisible(search.receiver) &&
    !GetWindow(search.receiver, GW_OWNER);
  auto exercise = [&](CLIPFORMAT format, bool expected, bool fast = false) {
    SetForegroundWindow(helper);
    auto pump = []() {
      MSG message;
      while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
        TranslateMessage(&message); DispatchMessageW(&message);
      }
    };
    pump();
    SetCursorPos(650, 450); mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
    Sleep(60); pump();
    auto movement = [&]() {
      Sleep(250);
      for (int i = 0; i < 30; ++i) { SetCursorPos(700 + i * (fast ? 12 : 1), 480); Sleep(25); }
      const bool visible = IsWindowVisible(search.receiver) != FALSE;
      wchar_t hit[256]{}; POINT point; GetCursorPos(&point);
      GetClassNameW(WindowFromPoint(point), hit, 256);
      std::wcout << L"probe=" << search.probe << L" visible=" << IsWindowVisible(search.probe) << L" hit=" << hit << std::endl;
      passed = passed && visible == expected;
      std::cout << "format=" << format << " visible=" << visible << " expected=" << expected << std::endl;
      if (format) {
        Sleep(100);
        keybd_event(VK_ESCAPE, 0, 0, 0);
        Sleep(50);
        keybd_event(VK_ESCAPE, 0, KEYEVENTF_KEYUP, 0);
      }
      mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
    };
    if (format) {
      std::thread mover(movement);
      auto payload = new Payload(format, fixture.wstring()); DWORD effect = 0;
      const auto result = DoDragDrop(payload, payload, DROPEFFECT_COPY, &effect);
      std::cout << "DoDragDrop result=" << std::hex << result << std::dec << std::endl;
      payload->Release(); mover.join();
      passed = passed && effect == DROPEFFECT_NONE;
    } else movement();
    Sleep(250);
    passed = passed && !IsWindowVisible(search.receiver);
  };
  const bool complete_drop = argc == 3 && !wcscmp(argv[2], L"--drop");
  if (passed && !complete_drop && !(argc == 3 && (!wcscmp(argv[2], L"--desktop-only") || !wcscmp(argv[2], L"--desktop-origin")))) {
    exercise(0, false);             // Mouse selection, no OLE payload.
    exercise(CF_UNICODETEXT, false); // Real OLE text drag.
    exercise(CF_HDROP, true);        // Real OLE filesystem folder drag.
    exercise(CF_HDROP, true, true);  // Fast motion must not miss the probe.
    exercise(0, false);             // No stale confirmation on the next gesture.
  }
  if (passed && complete_drop) {
    Sleep(1000);
    SetForegroundWindow(helper);
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) DispatchMessageW(&message);
    SetCursorPos(650, 450); mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
    Sleep(60);
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) DispatchMessageW(&message);
    std::thread mover([&]() {
      Sleep(250);
      for (int i = 0; i < 30; ++i) { SetCursorPos(700 + i, 480); Sleep(25); }
      if (!IsWindowVisible(search.receiver)) {
        keybd_event(VK_ESCAPE, 0, 0, 0); Sleep(50); keybd_event(VK_ESCAPE, 0, KEYEVENTF_KEYUP, 0);
      } else {
        RECT rect{}; GetWindowRect(search.receiver, &rect);
        const POINT target{(rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2};
        for (int i = 1; i <= 15; ++i) {
          SetCursorPos(729 + (target.x - 729) * i / 15, 480 + (target.y - 480) * i / 15);
          Sleep(25);
        }
        Sleep(200);
        // Verify this isolated instance owns the target before releasing.
        // A normal app instance may also reveal its own receiver during this
        // test. Raise only the isolated target before moving into it again.
        DWORD owner = 0;
        for (int attempt = 0; attempt < 20; ++attempt) {
          SetWindowPos(search.receiver, HWND_TOPMOST, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
          SetCursorPos(target.x + (attempt % 2), target.y);
          Sleep(20);
          GetWindowThreadProcessId(WindowFromPoint(target), &owner);
          if (owner == process.dwProcessId) break;
        }
        std::cout << "isolated drop target owner=" << owner << " expected=" << process.dwProcessId << std::endl;
        if (owner != process.dwProcessId) {
          keybd_event(VK_ESCAPE, 0, 0, 0); Sleep(50); keybd_event(VK_ESCAPE, 0, KEYEVENTF_KEYUP, 0);
        }
      }
      mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
    });
    auto payload = new Payload(CF_HDROP, fixture.wstring()); DWORD effect = 0;
    const auto result = DoDragDrop(payload, payload, DROPEFFECT_COPY, &effect);
    payload->Release(); mover.join();
    for (int i = 0; i < 80 && !search.transfer; ++i) { Sleep(100); EnumWindows(Find, reinterpret_cast<LPARAM>(&search)); }
    passed = result == DRAGDROP_S_DROP && effect == DROPEFFECT_COPY && search.transfer && IsWindowVisible(search.transfer);
    std::cout << "complete drop result=" << std::hex << result << std::dec << " effect=" << effect << " transfer=" << search.transfer << " visible=" << IsWindowVisible(search.transfer) << std::endl;
    if (passed) {
      Sleep(1000);
      RECT rect{}; GetWindowRect(search.transfer, &rect);
      const int width = rect.right - rect.left, height = rect.bottom - rect.top;
      HDC screen = GetDC(nullptr), dc = CreateCompatibleDC(screen);
      HBITMAP bitmap = CreateCompatibleBitmap(screen, width, height);
      auto old = SelectObject(dc, bitmap);
      PrintWindow(search.transfer, dc, 2);
      SelectObject(dc, old);
      BITMAPINFO info{}; info.bmiHeader = {sizeof(BITMAPINFOHEADER), width, height, 1, 32, BI_RGB};
      std::vector<BYTE> pixels(width * height * 4);
      GetDIBits(dc, bitmap, 0, height, pixels.data(), &info, DIB_RGB_COLORS);
      BITMAPFILEHEADER header{}; header.bfType = 0x4d42; header.bfOffBits = sizeof(header) + sizeof(info.bmiHeader); header.bfSize = header.bfOffBits + static_cast<DWORD>(pixels.size());
      std::ofstream output("build/native-tests/drop-transfer.bmp", std::ios::binary);
      output.write(reinterpret_cast<const char*>(&header), sizeof(header));
      output.write(reinterpret_cast<const char*>(&info.bmiHeader), sizeof(info.bmiHeader));
      output.write(reinterpret_cast<const char*>(pixels.data()), pixels.size());
      DeleteObject(bitmap); DeleteDC(dc); ReleaseDC(nullptr, screen);
    }
  }
  mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0); SetCursorPos(original.x, original.y);
  DestroyWindow(helper);
  if (passed && argc == 3 && !complete_drop) passed = DesktopDrag(search.receiver, !wcscmp(argv[2], L"--desktop-origin"));
  TerminateProcess(process.hProcess, 0); WaitForSingleObject(process.hProcess, 5000);
  CloseHandle(process.hProcess); CloseHandle(process.hThread);
  std::error_code error; std::filesystem::remove_all(data, error);
  OleUninitialize();
  std::cout << (passed ? "PASS" : "FAIL") << std::endl;
  return passed ? 0 : 1;
}
