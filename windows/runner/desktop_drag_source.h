#pragma once
#include <windows.h>

// Only filesystem items hit directly on the shell desktop qualify. Selection
// elsewhere, empty-space marquee selection and icon-label editing do not.
bool IsDesktopFileDragOrigin(HWND source, POINT origin);
