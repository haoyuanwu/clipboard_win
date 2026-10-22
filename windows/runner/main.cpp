#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::OleInitialize(nullptr);
  // UI verification runs without clipboard capture in a separate process.
  // Normal launches retain the single-instance behavior.
  const bool preview = wcsstr(GetCommandLineW(), L"--preview-instance") &&
    wcsstr(GetCommandLineW(), L"--no-capture") && wcsstr(GetCommandLineW(), L"--no-startup") &&
    wcsstr(GetCommandLineW(), L"--data-dir");
  std::wstring mutex_name = L"Local\\SuperClipboard.Windows";
  if (preview) mutex_name += L".Preview." + std::to_wstring(GetCurrentProcessId());
  HANDLE instance_mutex = CreateMutex(nullptr, FALSE, mutex_name.c_str());
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    PostMessage(HWND_BROADCAST, RegisterWindowMessage(L"SuperClipboard.ShowMain"), 0, 0);
    if (instance_mutex) CloseHandle(instance_mutex);
    ::OleUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(180, 100);
  Win32Window::Size size(440, 640);
  if (!window.Create(L"SuperClipboard", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (instance_mutex) CloseHandle(instance_mutex);
  ::OleUninitialize();
  return EXIT_SUCCESS;
}
