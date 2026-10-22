#ifndef SUPERCLIPBOARD_PLATFORM_BRIDGE_H_
#define SUPERCLIPBOARD_PLATFORM_BRIDGE_H_
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>
#include <optional>
#include <string>
class PlatformBridge {
 public:
  PlatformBridge(flutter::BinaryMessenger* messenger, HWND window, HWND view,
                 const std::string& mode);
  ~PlatformBridge();
  std::optional<LRESULT> Handle(UINT message, WPARAM wp, LPARAM lp);
  void Notify(const std::string& method, const flutter::EncodableValue& value = {});
  void ShowWindowForMode(const std::string& mode);
 private:
  void Hide();
  void ConfigureGlass(bool dark, bool opaque);
  HWND window_, view_;
  std::string mode_;
  bool ready_ = false;
  bool windows_style_ = true;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  class DropTarget;
  DropTarget* drop_ = nullptr;
};
#endif
