#include "clipboard_native.h"
#include <shellapi.h>
#include <shobjidl.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <gdiplus.h>
#include <wrl/client.h>
#include <filesystem>
#include <fstream>
#include <vector>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <sstream>
#include <map>
using Microsoft::WRL::ComPtr;
namespace clipboard_native {
namespace {
std::wstring cache_path;
DWORD own_sequence = 0;
ULONG_PTR gdiplus_token = 0;
unsigned int serial = 0;
void Init() {
  if (!gdiplus_token) { Gdiplus::GdiplusStartupInput input; Gdiplus::GdiplusStartup(&gdiplus_token, &input, nullptr); }
}
std::wstring NewPath(const wchar_t* prefix) {
  return cache_path + L"/" + prefix + std::to_wstring(GetTickCount64()) + L"-" + std::to_wstring(serial++) + L".png";
}
bool SavePng(Gdiplus::Bitmap& bitmap, const std::wstring& path) {
  const CLSID png = {0x557cf406, 0x1a04, 0x11d3, {0x9a,0x73,0x00,0x00,0xf8,0x1e,0xf3,0x2e}};
  return bitmap.Save(path.c_str(), &png) == Gdiplus::Ok;
}
std::vector<uint8_t> Bytes(HGLOBAL memory) {
  std::vector<uint8_t> result;
  if (!memory) return result;
  const auto size = GlobalSize(memory);
  if (!size || size > 256 * 1024 * 1024) return result;
  auto p = static_cast<const uint8_t*>(GlobalLock(memory));
  if (p) { result.assign(p, p + size); GlobalUnlock(memory); }
  return result;
}
HGLOBAL Alloc(const void* data, size_t size) {
  auto memory = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, size);
  if (!memory) return nullptr;
  auto target = GlobalLock(memory);
  if (!target) { GlobalFree(memory); return nullptr; }
  memcpy(target, data, size); GlobalUnlock(memory); return memory;
}
std::string NarrowData(const std::vector<uint8_t>& bytes) {
  auto end = std::find(bytes.begin(), bytes.end(), static_cast<uint8_t>(0));
  return std::string(bytes.begin(), end);
}
flutter::EncodableList FileList(HGLOBAL memory) {
  flutter::EncodableList paths;
  auto count = DragQueryFile(static_cast<HDROP>(memory), 0xffffffff, nullptr, 0);
  for (UINT i = 0; i < count; ++i) {
    UINT size = DragQueryFile(static_cast<HDROP>(memory), i, nullptr, 0);
    std::wstring path(size + 1, L'\0'); DragQueryFile(static_cast<HDROP>(memory), i, path.data(), size + 1);
    path.resize(size); paths.emplace_back(Utf8(path));
  }
  return paths;
}
std::vector<uint8_t> DropBytes(const flutter::EncodableList& paths) {
  std::wstring joined;
  for (const auto& path : paths) {
    auto wide = Wide(std::get<std::string>(path)); std::replace(wide.begin(), wide.end(), L'/', L'\\');
    joined += wide; joined += L'\0';
  }
  joined += L'\0';
  std::vector<uint8_t> bytes(sizeof(DROPFILES) + joined.size() * sizeof(wchar_t), 0);
  auto header = reinterpret_cast<DROPFILES*>(bytes.data()); header->pFiles = sizeof(DROPFILES); header->fWide = TRUE;
  memcpy(bytes.data() + sizeof(DROPFILES), joined.data(), joined.size() * sizeof(wchar_t)); return bytes;
}
// Materialize virtual file streams before acknowledging the OLE drop. No partial group is returned.
bool ReadVirtualFiles(IDataObject* object, const std::vector<uint8_t>& descriptor, Map& data) {
  if (cache_path.empty() || descriptor.size() < sizeof(UINT)) return false;
  const auto* group = reinterpret_cast<const FILEGROUPDESCRIPTORW*>(descriptor.data());
  if (!group->cItems || group->cItems > 10000 || group->cItems > (descriptor.size() - sizeof(UINT)) / sizeof(FILEDESCRIPTORW)) return false;
  auto folder = std::filesystem::path(NewPath(L"drop-")).replace_extension();
  std::error_code error;
  std::filesystem::create_directories(folder, error);
  if (error) return false;
  flutter::EncodableList paths;
  bool ok = true;
  for (UINT index = 0; index < group->cItems && ok; ++index) {
    const auto& file = group->fgd[index];
    const auto end = std::find(std::begin(file.cFileName), std::end(file.cFileName), L'\0');
    const std::wstring name(file.cFileName, end);
    if (name.empty() || name == L"." || name == L".." || name.find_first_of(L"<>:\"/\\|?*") != std::wstring::npos) { ok = false; break; }
    const auto container = folder / std::to_wstring(index);
    const auto target = container / name;
    std::filesystem::create_directories(container, error);
    if (error) { ok = false; break; }
    if ((file.dwFlags & FD_ATTRIBUTES) && (file.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
      std::filesystem::create_directory(target, error);
      if (error) { ok = false; break; }
    } else {
      FORMATETC format{static_cast<CLIPFORMAT>(RegisterClipboardFormat(CFSTR_FILECONTENTS)), nullptr,
        DVASPECT_CONTENT, static_cast<LONG>(index), TYMED_ISTREAM | TYMED_HGLOBAL};
      STGMEDIUM medium{};
      if (FAILED(object->GetData(&format, &medium))) { ok = false; break; }
      std::ofstream output(target, std::ios::binary);
      uint64_t total = 0;
      if (medium.tymed == TYMED_ISTREAM && medium.pstm) {
        char buffer[65536]; ULONG count = 0; HRESULT status;
        do {
          status = medium.pstm->Read(buffer, sizeof(buffer), &count);
          if (FAILED(status)) { ok = false; break; }
          output.write(buffer, count); total += count;
        } while (count && status == S_OK);
      } else if (medium.tymed == TYMED_HGLOBAL && medium.hGlobal) {
        auto size = GlobalSize(medium.hGlobal);
        if (file.dwFlags & FD_FILESIZE) {
          const uint64_t expected = (static_cast<uint64_t>(file.nFileSizeHigh) << 32) | file.nFileSizeLow;
          if (expected > size) ok = false; else size = static_cast<SIZE_T>(expected);
        }
        auto content = GlobalLock(medium.hGlobal);
        if (!content && size) ok = false;
        else if (content) { output.write(static_cast<const char*>(content), static_cast<std::streamsize>(size)); total = size; GlobalUnlock(medium.hGlobal); }
      } else ok = false;
      output.close();
      if (!output || ((file.dwFlags & FD_FILESIZE) && total != ((static_cast<uint64_t>(file.nFileSizeHigh) << 32) | file.nFileSizeLow))) ok = false;
      ReleaseStgMedium(&medium);
    }
    paths.emplace_back(Utf8(target.wstring()));
  }
  if (!ok) { std::filesystem::remove_all(folder, error); return false; }
  data[Value("paths")] = Value(paths);
  data[Value("temporaryDirectory")] = Value(Utf8(folder.wstring()));
  return true;
}
void Source(Map& data) {
  HWND owner = GetClipboardOwner();
  if (!owner) owner = GetForegroundWindow();
  DWORD pid = 0; GetWindowThreadProcessId(owner, &pid);
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  std::wstring exe(32768, L'\0'); DWORD length = static_cast<DWORD>(exe.size());
  if (!process || !QueryFullProcessImageName(process, 0, exe.data(), &length)) {
    if (process) CloseHandle(process); data[Value("source")] = Value("未知应用"); return;
  }
  CloseHandle(process); exe.resize(length);
  auto name = std::filesystem::path(exe).stem().wstring();
  if (name == L"explorer") name = L"文件资源管理器";
  else if (name == L"msedge") name = L"Microsoft Edge";
  else if (name == L"chrome") name = L"Google Chrome";
  else if (name == L"Code") name = L"Visual Studio Code";
  else if (name == L"notepad") name = L"记事本";
  data[Value("source")] = Value(Utf8(name));
  SHFILEINFO info{};
  if (SHGetFileInfo(exe.c_str(), 0, &info, sizeof(info), SHGFI_ICON | SHGFI_LARGEICON)) {
    std::wstringstream hash; hash << std::hex << std::hash<std::wstring>{}(exe);
    const auto path = cache_path + L"/app-" + hash.str() + L".png";
    Gdiplus::Bitmap bitmap(32, 32, PixelFormat32bppARGB);
    Gdiplus::Graphics graphics(&bitmap); graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
    HDC dc = graphics.GetHDC(); DrawIconEx(dc, 0, 0, info.hIcon, 32, 32, 0, nullptr, DI_NORMAL); graphics.ReleaseHDC(dc);
    if (SavePng(bitmap, path)) data[Value("sourceIcon")] = Value(Utf8(path));
    double best = 0; int64_t tint = 0xff454d61;
    for (UINT y = 2; y < 30; y += 2) for (UINT x = 2; x < 30; x += 2) {
      Gdiplus::Color c; bitmap.GetPixel(x, y, &c);
      const double r = c.GetR() / 255., g = c.GetG() / 255., b = c.GetB() / 255.;
      const double saturation = std::max({r,g,b}) - std::min({r,g,b});
      const double score = saturation * (1 - std::abs((r + g + b) / 3 - .5));
      if (c.GetA() > 140 && score > best) { best = score; tint = 0xff000000LL | (c.GetR() << 16) | (c.GetG() << 8) | c.GetB(); }
    }
    data[Value("tint")] = Value(tint); DestroyIcon(info.hIcon);
  }
}
}
std::wstring Wide(const std::string& s) {
  if (s.empty()) return {};
  int size = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring result(size, L'\0'); MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), result.data(), size); return result;
}
std::string Utf8(const std::wstring& s) {
  if (s.empty()) return {};
  int size = WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0, nullptr, nullptr);
  std::string result(size, '\0'); WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), result.data(), size, nullptr, nullptr); return result;
}
std::string String(const Map& m, const char* key) {
  auto i = m.find(Value(key)); return i == m.end() || !std::holds_alternative<std::string>(i->second) ? "" : std::get<std::string>(i->second);
}
void SetCache(const std::string& path) { Init(); cache_path = Wide(path); }
bool IsOwnClipboard() { return own_sequence != 0 && own_sequence == GetClipboardSequenceNumber(); }
Value Read(HWND window, IDataObject* object) {
  Init();
  if (!object && !OpenClipboard(window)) return Value();
  Map data;
  auto get = [&](CLIPFORMAT format) -> std::vector<uint8_t> {
    if (!object) return Bytes(GetClipboardData(format));
    FORMATETC fmt{format, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL}; STGMEDIUM medium{};
    if (FAILED(object->GetData(&fmt, &medium))) return {};
    auto bytes = Bytes(medium.hGlobal); ReleaseStgMedium(&medium); return bytes;
  };
  auto files = get(CF_HDROP);
  auto descriptors = object && files.empty() ? get(static_cast<CLIPFORMAT>(RegisterClipboardFormat(CFSTR_FILEDESCRIPTORW))) : std::vector<uint8_t>{};
  if (!files.empty()) {
    HGLOBAL memory = Alloc(files.data(), files.size()); data[Value("paths")] = Value(FileList(memory)); GlobalFree(memory);
  } else if (!descriptors.empty()) {
    if (!ReadVirtualFiles(object, descriptors, data)) data[Value("error")] = Value("文件数据未能完整读取，未导入任何文件。");
  } else {
    auto png = get(static_cast<CLIPFORMAT>(RegisterClipboardFormat(L"PNG")));
    std::wstring image;
    if (!png.empty()) {
      image = NewPath(L"clip-"); std::ofstream out(std::filesystem::path(image), std::ios::binary);
      out.write(reinterpret_cast<const char*>(png.data()), static_cast<std::streamsize>(png.size()));
    } else {
      auto dib = get(CF_DIBV5); if (dib.empty()) dib = get(CF_DIB);
      if (dib.size() >= sizeof(BITMAPINFOHEADER)) {
        auto header = reinterpret_cast<const BITMAPINFOHEADER*>(dib.data());
        size_t offset = header->biSize;
        if (header->biBitCount <= 8) offset += (header->biClrUsed ? header->biClrUsed : (1ULL << header->biBitCount)) * sizeof(RGBQUAD);
        if (header->biSize == sizeof(BITMAPINFOHEADER) && header->biCompression == BI_BITFIELDS) offset += 12;
        if (offset < dib.size() && header->biWidth > 0 && std::abs(header->biHeight) > 0) {
          Gdiplus::Bitmap bitmap(reinterpret_cast<const BITMAPINFO*>(dib.data()), const_cast<uint8_t*>(dib.data() + offset));
          image = NewPath(L"clip-"); if (!SavePng(bitmap, image)) image.clear();
        }
      }
    }
    if (!image.empty()) data[Value("imagePath")] = Value(Utf8(image));
    else {
      auto text = get(CF_UNICODETEXT);
      if (text.size() >= 2) {
        const auto wide = reinterpret_cast<const wchar_t*>(text.data());
        const auto max = text.size() / sizeof(wchar_t);
        size_t size = 0; while (size < max && wide[size]) ++size;
        data[Value("text")] = Value(Utf8(std::wstring(wide, size)));
        data[Value("html")] = Value(NarrowData(get(static_cast<CLIPFORMAT>(RegisterClipboardFormat(L"HTML Format")))));
        auto rtf = NarrowData(get(static_cast<CLIPFORMAT>(RegisterClipboardFormat(L"Rich Text Format"))));
        std::wstring latin; for (unsigned char c : rtf) latin += static_cast<wchar_t>(c);
        data[Value("rtf")] = Value(Utf8(latin));
      }
    }
  }
  if (object) data[Value("fingerprint")] = Value(NarrowData(get(static_cast<CLIPFORMAT>(RegisterClipboardFormat(L"SuperClipboard.Entry")))));
  if (!object) { Source(data); CloseClipboard(); }
  else data[Value("source")] = Value("拖入内容");
  return data.empty() ? Value() : Value(data);
}
bool Write(HWND window, const Map& entry) {
  Init();
  std::vector<std::pair<UINT, HGLOBAL>> formats;
  auto add = [&](UINT format, const void* data, size_t size) {
    HGLOBAL h = Alloc(data, size); if (h) formats.emplace_back(format, h);
  };
  const auto kind = String(entry, "kind");
  if (kind == "text") {
    auto text = Wide(String(entry, "text")); add(CF_UNICODETEXT, text.c_str(), (text.size() + 1) * sizeof(wchar_t));
    for (auto field : {"html", "rtf"}) {
      auto value = String(entry, field);
      if (field == std::string("rtf")) {
        auto wide = Wide(value); value.clear(); for (auto c : wide) value += static_cast<char>(c & 0xff);
      }
      if (!value.empty()) add(RegisterClipboardFormat(field == std::string("html") ? L"HTML Format" : L"Rich Text Format"), value.c_str(), value.size() + 1);
    }
  } else if (kind == "image") {
    const auto path = Wide(String(entry, "imagePath"));
    std::ifstream in(std::filesystem::path(path), std::ios::binary);
    std::vector<uint8_t> png((std::istreambuf_iterator<char>(in)), {});
    if (png.empty()) return false;
    add(RegisterClipboardFormat(L"PNG"), png.data(), png.size());
    Gdiplus::Bitmap bitmap(path.c_str());
    const auto w = bitmap.GetWidth(), h = bitmap.GetHeight();
    if (w && h && w < 32768 && h < 32768) {
      Gdiplus::BitmapData bits{}; Gdiplus::Rect rect(0, 0, static_cast<INT>(w), static_cast<INT>(h));
      if (bitmap.LockBits(&rect, Gdiplus::ImageLockModeRead, PixelFormat32bppARGB, &bits) == Gdiplus::Ok) {
        std::vector<uint8_t> dib(sizeof(BITMAPV5HEADER) + static_cast<size_t>(w) * h * 4, 0);
        auto header = reinterpret_cast<BITMAPV5HEADER*>(dib.data()); header->bV5Size = sizeof(BITMAPV5HEADER);
        header->bV5Width = static_cast<LONG>(w); header->bV5Height = -static_cast<LONG>(h); header->bV5Planes = 1;
        header->bV5BitCount = 32; header->bV5Compression = BI_BITFIELDS;
        header->bV5RedMask = 0x00ff0000; header->bV5GreenMask = 0x0000ff00; header->bV5BlueMask = 0x000000ff; header->bV5AlphaMask = 0xff000000;
        header->bV5CSType = LCS_sRGB;
        for (UINT y = 0; y < h; ++y) memcpy(dib.data() + sizeof(BITMAPV5HEADER) + static_cast<size_t>(y) * w * 4,
          static_cast<uint8_t*>(bits.Scan0) + static_cast<ptrdiff_t>(y) * bits.Stride, static_cast<size_t>(w) * 4);
        bitmap.UnlockBits(&bits); add(CF_DIBV5, dib.data(), dib.size());
      }
    }
  } else {
    auto it = entry.find(Value("paths"));
    if (it == entry.end() || !std::holds_alternative<flutter::EncodableList>(it->second)) return false;
    auto bytes = DropBytes(std::get<flutter::EncodableList>(it->second)); add(CF_HDROP, bytes.data(), bytes.size());
  }
  if (formats.empty()) return false;
  if (!OpenClipboard(window)) { for (auto& f : formats) GlobalFree(f.second); return false; }
  EmptyClipboard(); bool success = false;
  for (auto& [format, memory] : formats) { if (SetClipboardData(format, memory)) success = true; else GlobalFree(memory); }
  CloseClipboard(); own_sequence = GetClipboardSequenceNumber(); return success;
}
std::string Thumbnail(const std::string& path) {
  Init(); ComPtr<IShellItemImageFactory> factory;
  if (FAILED(SHCreateItemFromParsingName(Wide(path).c_str(), nullptr, IID_PPV_ARGS(&factory)))) return "";
  HBITMAP handle = nullptr;
  if (FAILED(factory->GetImage({640, 360}, SIIGBF_THUMBNAILONLY | SIIGBF_BIGGERSIZEOK, &handle))) return "";
  Gdiplus::Bitmap bitmap(handle, nullptr); auto file = NewPath(L"video-");
  bool ok = SavePng(bitmap, file); DeleteObject(handle); return ok ? Utf8(file) : "";
}

namespace {
class DragData : public IDataObject, public IDropSource {
 public:
  DragData(CLIPFORMAT format, std::vector<uint8_t> bytes) { formats_[format] = std::move(bytes); }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** out) override {
    if (iid == IID_IUnknown || iid == IID_IDataObject) *out = static_cast<IDataObject*>(this);
    else if (iid == IID_IDropSource) *out = static_cast<IDropSource*>(this);
    else { *out = nullptr; return E_NOINTERFACE; }
    AddRef(); return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override { auto count = --refs_; if (!count) delete this; return count; }
  HRESULT STDMETHODCALLTYPE GetData(FORMATETC* f, STGMEDIUM* out) override {
    if (FAILED(QueryGetData(f))) return DV_E_FORMATETC;
    const auto& bytes = formats_[f->cfFormat];
    out->tymed = TYMED_HGLOBAL; out->hGlobal = Alloc(bytes.data(), bytes.size()); out->pUnkForRelease = nullptr;
    return out->hGlobal ? S_OK : E_OUTOFMEMORY;
  }
  HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC*, STGMEDIUM*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC* f) override { return formats_.count(f->cfFormat) && (f->tymed & TYMED_HGLOBAL) ? S_OK : DV_E_FORMATETC; }
  HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC*, FORMATETC* f) override { f->ptd = nullptr; return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE SetData(FORMATETC* f, STGMEDIUM* medium, BOOL release) override {
    if (medium->tymed != TYMED_HGLOBAL) return DV_E_TYMED;
    formats_[f->cfFormat] = Bytes(medium->hGlobal);
    if (release) ReleaseStgMedium(medium);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD direction, IEnumFORMATETC** out) override {
    if (direction != DATADIR_GET) return E_NOTIMPL;
    std::vector<FORMATETC> formats;
    for (const auto& pair : formats_) formats.push_back({pair.first, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL});
    return SHCreateStdEnumFmtEtc(static_cast<UINT>(formats.size()), formats.data(), out);
  }
  HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC*, DWORD, IAdviseSink*, DWORD*) override { return OLE_E_ADVISENOTSUPPORTED; }
  HRESULT STDMETHODCALLTYPE DUnadvise(DWORD) override { return OLE_E_ADVISENOTSUPPORTED; }
  HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA**) override { return OLE_E_ADVISENOTSUPPORTED; }
  HRESULT STDMETHODCALLTYPE QueryContinueDrag(BOOL escape, DWORD keys) override {
    if (escape) return DRAGDROP_S_CANCEL; return (keys & MK_LBUTTON) ? S_OK : DRAGDROP_S_DROP;
  }
  HRESULT STDMETHODCALLTYPE GiveFeedback(DWORD) override { return DRAGDROP_S_USEDEFAULTCURSORS; }
 private:
  ULONG refs_ = 1; std::map<CLIPFORMAT, std::vector<uint8_t>> formats_;
};
}
void Drag(HWND window, const Map& entry) {
  if (!(GetAsyncKeyState(VK_LBUTTON) & 0x8000)) return;
  const auto kind = String(entry, "kind");
  DragData* data = nullptr;
  if (kind == "text") {
    auto text = Wide(String(entry, "text"));
    std::vector<uint8_t> bytes((text.size() + 1) * sizeof(wchar_t)); memcpy(bytes.data(), text.c_str(), bytes.size());
    data = new DragData(CF_UNICODETEXT, std::move(bytes));
  } else {
    flutter::EncodableList paths;
    if (kind == "image") paths.emplace_back(String(entry, "imagePath"));
    else {
      auto it = entry.find(Value("paths")); if (it == entry.end()) return;
      paths = std::get<flutter::EncodableList>(it->second);
      // Windows accepts a native multi-file selection; never infer a parent folder.

    }
    data = new DragData(CF_HDROP, DropBytes(paths));
  }
  if (kind == "text") {
    for (auto name : {"html", "rtf"}) {
      auto content = String(entry, name);
      if (std::string(name) == "rtf") {
        auto wide = Wide(content); content.clear();
        for (auto c : wide) content += static_cast<char>(c & 0xff);
      }
      if (content.empty()) continue;
      FORMATETC format{static_cast<CLIPFORMAT>(RegisterClipboardFormat(std::string(name) == "html" ? L"HTML Format" : L"Rich Text Format")), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
      STGMEDIUM medium{}; medium.tymed = TYMED_HGLOBAL; medium.hGlobal = Alloc(content.c_str(), content.size() + 1);
      if (medium.hGlobal) data->SetData(&format, &medium, TRUE);
    }
  }
  auto fingerprint = String(entry, "fingerprint");
  FORMATETC identity_format{static_cast<CLIPFORMAT>(RegisterClipboardFormat(L"SuperClipboard.Entry")), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM identity{}; identity.tymed = TYMED_HGLOBAL; identity.hGlobal = Alloc(fingerprint.c_str(), fingerprint.size() + 1);
  if (identity.hGlobal) data->SetData(&identity_format, &identity, TRUE);
  // Supply one system drag image, so Windows handles tracking and cancellation.
  ComPtr<IDragSourceHelper> helper;
  if (SUCCEEDED(CoCreateInstance(CLSID_DragDropHelper, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&helper)))) {
    Init();
    Gdiplus::Bitmap preview(180, 104, PixelFormat32bppARGB);
    Gdiplus::Graphics graphics(&preview);
    graphics.Clear(Gdiplus::Color(240, 240, 244, 250));
    auto path = String(entry, kind == "image" ? "imagePath" : "previewPath");
    if (!path.empty()) {
      Gdiplus::Bitmap image(Wide(path).c_str());
      if (image.GetWidth() && image.GetHeight()) {
        const float ratio = std::min(172.f / image.GetWidth(), 96.f / image.GetHeight());
        const float width = image.GetWidth() * ratio, height = image.GetHeight() * ratio;
        graphics.DrawImage(&image, (180.f - width) / 2, (104.f - height) / 2, width, height);
      }
    } else {
      auto label = Wide(String(entry, kind == "text" ? "text" : "title"));
      if (label.size() > 160) label.resize(160);
      Gdiplus::Font font(L"Microsoft YaHei UI", 12.f, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
      Gdiplus::SolidBrush brush(Gdiplus::Color(255, 28, 35, 46));
      Gdiplus::RectF bounds(12.f, 12.f, 156.f, 80.f);
      graphics.DrawString(label.c_str(), static_cast<INT>(label.size()), &font, bounds, nullptr, &brush);
    }
    HBITMAP bitmap = nullptr;
    preview.GetHBITMAP(Gdiplus::Color(0, 0, 0, 0), &bitmap);
    SHDRAGIMAGE drag_image{}; drag_image.sizeDragImage = {180, 104};
    drag_image.ptOffset = {20, 20}; drag_image.hbmpDragImage = bitmap; drag_image.crColorKey = CLR_NONE;
    helper->InitializeFromBitmap(&drag_image, data);
    DeleteObject(bitmap);
  }
  DWORD effect = 0;
  SHDoDragDrop(window, data, data, DROPEFFECT_COPY, &effect);
  data->Release();
}
}
