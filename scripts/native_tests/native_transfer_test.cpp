#include "clipboard_native.h"
#include <shlobj.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <cstring>
#include <vector>
#include <shellapi.h>
using clipboard_native::Value;
using clipboard_native::Map;
class VirtualFiles : public IDataObject {
 public:
  bool fail_second = false, bad_name = false, wrong_size = false;
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** out) override {
    if (iid == IID_IUnknown || iid == IID_IDataObject) { *out = this; AddRef(); return S_OK; }
    *out = nullptr; return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override { auto refs = --refs_; if (!refs) delete this; return refs; }
  HRESULT STDMETHODCALLTYPE GetData(FORMATETC* format, STGMEDIUM* medium) override {
    *medium = {};
    if (format->cfFormat == RegisterClipboardFormat(CFSTR_FILEDESCRIPTORW)) {
      const size_t size = sizeof(UINT) + 2 * sizeof(FILEDESCRIPTORW);
      auto memory = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, size);
      auto group = static_cast<FILEGROUPDESCRIPTORW*>(GlobalLock(memory));
      group->cItems = 2;
      for (int i = 0; i < 2; i++) {
        group->fgd[i].dwFlags = FD_FILESIZE;
        group->fgd[i].nFileSizeLow = static_cast<DWORD>(contents[i].size() + (wrong_size ? 1 : 0));
        wcscpy_s(group->fgd[i].cFileName, bad_name ? L"../escape.txt" : i == 0 ? L"文档.txt" : L"attachment.txt");
      }
      GlobalUnlock(memory); medium->tymed = TYMED_HGLOBAL; medium->hGlobal = memory; return S_OK;
    }
    if (format->cfFormat == RegisterClipboardFormat(CFSTR_FILECONTENTS)) {
      if (format->lindex < 0 || format->lindex > 1 || (fail_second && format->lindex == 1)) return DV_E_FORMATETC;
      const auto& bytes = contents[format->lindex];
      if (format->lindex == 0) {
        medium->tymed = TYMED_HGLOBAL; medium->hGlobal = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
        auto p = GlobalLock(medium->hGlobal); memcpy(p, bytes.data(), bytes.size()); GlobalUnlock(medium->hGlobal);
      } else {
        medium->tymed = TYMED_ISTREAM;
        CreateStreamOnHGlobal(nullptr, TRUE, &medium->pstm);
        ULONG written; medium->pstm->Write(bytes.data(), static_cast<ULONG>(bytes.size()), &written);
        LARGE_INTEGER start{}; medium->pstm->Seek(start, STREAM_SEEK_SET, nullptr);
      }
      return S_OK;
    }
    return DV_E_FORMATETC;
  }
  HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC*, STGMEDIUM*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC*, FORMATETC*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE SetData(FORMATETC*, STGMEDIUM*, BOOL) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD, IEnumFORMATETC**) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC*, DWORD, IAdviseSink*, DWORD*) override { return OLE_E_ADVISENOTSUPPORTED; }
  HRESULT STDMETHODCALLTYPE DUnadvise(DWORD) override { return OLE_E_ADVISENOTSUPPORTED; }
  HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA**) override { return OLE_E_ADVISENOTSUPPORTED; }
  std::vector<std::string> contents{"first virtual file", "second stream"};
 private: ULONG refs_ = 1;
};
class LocalFolder : public VirtualFiles {
 public:
  std::wstring path;
  std::string identity;
  HRESULT STDMETHODCALLTYPE GetData(FORMATETC* format, STGMEDIUM* medium) override {
    *medium = {};
    if (format->cfFormat == CF_HDROP) {
      const auto bytes = sizeof(DROPFILES) + (path.size() + 2) * sizeof(wchar_t);
      auto memory = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, bytes);
      auto drop = static_cast<DROPFILES*>(GlobalLock(memory));
      drop->pFiles = sizeof(DROPFILES); drop->fWide = TRUE;
      memcpy(reinterpret_cast<char*>(drop) + sizeof(DROPFILES), path.c_str(), path.size() * sizeof(wchar_t));
      GlobalUnlock(memory);
      medium->tymed = TYMED_HGLOBAL; medium->hGlobal = memory; return S_OK;
    }
    if (format->cfFormat == RegisterClipboardFormat(L"SuperClipboard.Entry") && !identity.empty()) {
      auto memory = GlobalAlloc(GMEM_MOVEABLE, identity.size() + 1);
      auto data = GlobalLock(memory); memcpy(data, identity.c_str(), identity.size() + 1); GlobalUnlock(memory);
      medium->tymed = TYMED_HGLOBAL; medium->hGlobal = memory; return S_OK;
    }
    return DV_E_FORMATETC;
  }
};
int main(int argc, char** argv) {
  if (argc != 2) return 2;
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const auto root = std::filesystem::absolute(argv[1]);
  std::filesystem::create_directories(root);
  clipboard_native::SetCache(clipboard_native::Utf8(root.wstring()));
  auto local = new LocalFolder;
  local->path = root.wstring();
  auto localValue = clipboard_native::Read(nullptr, local);
  const auto* localData = std::get_if<Map>(&localValue);
  if (!localData || localData->count(Value("fingerprint")) || !localData->count(Value("paths"))) return 20;
  local->identity = "known-internal-group";
  localValue = clipboard_native::Read(nullptr, local);
  localData = std::get_if<Map>(&localValue);
  if (!localData || clipboard_native::String(*localData, "fingerprint") != local->identity) return 21;
  local->Release();
  auto source = new VirtualFiles;
  auto value = clipboard_native::Read(nullptr, source);
  const auto* data = std::get_if<Map>(&value);
  if (!data || data->count(Value("error")) || !data->count(Value("paths"))) return 3;
  auto paths = std::get<flutter::EncodableList>(data->at(Value("paths")));
  if (paths.size() != 2) return 4;
  for (size_t i = 0; i < paths.size(); i++) {
    std::ifstream file(std::filesystem::path(clipboard_native::Wide(std::get<std::string>(paths[i]))), std::ios::binary);
    std::string contents((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    if (contents != source->contents[i]) return 5;
  }
  const auto staging = std::filesystem::path(clipboard_native::Wide(clipboard_native::String(*data, "temporaryDirectory")));
  std::filesystem::remove_all(staging);
  for (int failure = 0; failure < 3; failure++) {
    source->fail_second = failure == 0; source->bad_name = failure == 1; source->wrong_size = failure == 2;
    value = clipboard_native::Read(nullptr, source);
    data = std::get_if<Map>(&value);
    if (!data || !data->count(Value("error")) || data->count(Value("paths"))) return 6 + failure;
    if (!std::filesystem::is_empty(root)) return 10 + failure;
  }
  source->Release(); CoUninitialize();
  std::cout << "Local folder drag identity and virtual files: mixed HGLOBAL/IStream, atomic failure, path validation and size validation passed.\n";
  return 0;
}
