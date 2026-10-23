#include "desktop_drag_source.h"
#include <oleacc.h>
#include <shlobj.h>
#include <exdisp.h>
#include <shlguid.h>
#include <servprov.h>
#include <wrl/client.h>

bool IsDesktopFileDragOrigin(HWND source, POINT origin) {
  wchar_t name[64]{};
  if (!source || !GetClassNameW(source, name, 64) || wcscmp(name, L"SysListView32")) return false;
  HWND parent = GetParent(source);
  if (!GetClassNameW(parent, name, 64) || wcscmp(name, L"SHELLDLL_DefView")) return false;

  using Microsoft::WRL::ComPtr;
  ComPtr<IAccessible> hit; VARIANT child{}, role{};
  if (FAILED(AccessibleObjectFromPoint(origin, &hit, &child))) return false;
  const auto result = hit->get_accRole(child, &role);
  VariantClear(&child);
  const bool item = SUCCEEDED(result) && role.vt == VT_I4 && role.lVal == ROLE_SYSTEM_LISTITEM;
  VariantClear(&role);
  if (!item) return false;

  ComPtr<IShellWindows> windows;
  if (FAILED(CoCreateInstance(CLSID_ShellWindows, nullptr, CLSCTX_LOCAL_SERVER, IID_PPV_ARGS(&windows)))) return false;
  VARIANT location{}, root{}; location.vt = VT_I4; location.lVal = CSIDL_DESKTOP;
  long handle = 0; ComPtr<IDispatch> dispatch;
  if (FAILED(windows->FindWindowSW(&location, &root, SWC_DESKTOP, &handle, SWFO_NEEDDISPATCH, &dispatch)) || !dispatch) return false;
  ComPtr<IServiceProvider> services; ComPtr<IShellBrowser> browser; ComPtr<IShellView> view;
  ComPtr<IFolderView> folder; ComPtr<IDataObject> selected;
  if (FAILED(dispatch.As(&services)) || FAILED(services->QueryService(SID_STopLevelBrowser, IID_PPV_ARGS(&browser))) ||
      FAILED(browser->QueryActiveShellView(&view)) || FAILED(view.As(&folder))) return false;
  HWND desktop_view = nullptr;
  if (FAILED(view->GetWindow(&desktop_view)) || desktop_view != parent) return false;
  if (FAILED(folder->Items(SVGIO_SELECTION, IID_PPV_ARGS(&selected))) || !selected) return false;
  FORMATETC files{CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  return SUCCEEDED(selected->QueryGetData(&files));
}
