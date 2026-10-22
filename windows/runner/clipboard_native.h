#ifndef SUPERCLIPBOARD_CLIPBOARD_NATIVE_H_
#define SUPERCLIPBOARD_CLIPBOARD_NATIVE_H_
#include <windows.h>
#include <oleidl.h>
#include <flutter/encodable_value.h>
#include <string>
namespace clipboard_native {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
std::wstring Wide(const std::string& s);
std::string Utf8(const std::wstring& s);
std::string String(const Map& m, const char* key);
void SetCache(const std::string& path);
Value Read(HWND window, IDataObject* object = nullptr);
bool Write(HWND window, const Map& entry);
std::string Thumbnail(const std::string& path);
void Drag(HWND window, const Map& entry);
bool IsOwnClipboard();
}
#endif
