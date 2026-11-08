#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

constexpr const wchar_t kWindowStateRegKey[] = L"Software\\OpenMoney";
constexpr const wchar_t kRegValueInitialized[] = L"WindowInitialized";
constexpr const wchar_t kRegValueMaximized[] = L"WindowMaximized";
constexpr const wchar_t kRegValueX[] = L"WindowX";
constexpr const wchar_t kRegValueY[] = L"WindowY";
constexpr const wchar_t kRegValueWidth[] = L"WindowWidth";
constexpr const wchar_t kRegValueHeight[] = L"WindowHeight";

void Win32Window::SaveWindowState(HWND hwnd) {
  if (!hwnd || !IsWindow(hwnd)) return;

  HKEY key;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kWindowStateRegKey, 0, nullptr,
                      REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &key,
                      nullptr) != ERROR_SUCCESS) {
    return;
  }

  DWORD dwOne = 1;
  RegSetValueExW(key, kRegValueInitialized, 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&dwOne), sizeof(DWORD));

  bool is_max = IsZoomed(hwnd);
  DWORD dwMax = is_max ? 1 : 0;
  RegSetValueExW(key, kRegValueMaximized, 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&dwMax), sizeof(DWORD));

  if (!is_max) {
    RECT rect{};
    if (GetWindowRect(hwnd, &rect)) {
      LONG x = rect.left;
      LONG y = rect.top;
      LONG w = rect.right - rect.left;
      LONG h = rect.bottom - rect.top;

      RegSetValueExW(key, kRegValueX, 0, REG_DWORD,
                     reinterpret_cast<const BYTE*>(&x), sizeof(DWORD));
      RegSetValueExW(key, kRegValueY, 0, REG_DWORD,
                     reinterpret_cast<const BYTE*>(&y), sizeof(DWORD));
      RegSetValueExW(key, kRegValueWidth, 0, REG_DWORD,
                     reinterpret_cast<const BYTE*>(&w), sizeof(DWORD));
      RegSetValueExW(key, kRegValueHeight, 0, REG_DWORD,
                     reinterpret_cast<const BYTE*>(&h), sizeof(DWORD));
    }
  }

  RegCloseKey(key);
}

static bool ReadSavedWindowState(RECT& out_rect, bool& out_is_maximized) {
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kWindowStateRegKey, 0, KEY_READ, &key) !=
      ERROR_SUCCESS) {
    return false;
  }

  DWORD initialized = 0;
  DWORD size = sizeof(DWORD);
  LSTATUS status = RegQueryValueExW(key, kRegValueInitialized, nullptr, nullptr,
                                    reinterpret_cast<BYTE*>(&initialized), &size);
  if (status != ERROR_SUCCESS || initialized == 0) {
    RegCloseKey(key);
    return false;
  }

  DWORD is_max = 0;
  size = sizeof(DWORD);
  RegQueryValueExW(key, kRegValueMaximized, nullptr, nullptr,
                   reinterpret_cast<BYTE*>(&is_max), &size);
  out_is_maximized = (is_max != 0);

  LONG x = 0, y = 0, w = 0, h = 0;
  size = sizeof(DWORD);
  bool has_pos = (RegQueryValueExW(key, kRegValueX, nullptr, nullptr,
                                   reinterpret_cast<BYTE*>(&x), &size) == ERROR_SUCCESS);
  size = sizeof(DWORD);
  has_pos = has_pos && (RegQueryValueExW(key, kRegValueY, nullptr, nullptr,
                                         reinterpret_cast<BYTE*>(&y), &size) == ERROR_SUCCESS);
  size = sizeof(DWORD);
  has_pos = has_pos && (RegQueryValueExW(key, kRegValueWidth, nullptr, nullptr,
                                         reinterpret_cast<BYTE*>(&w), &size) == ERROR_SUCCESS);
  size = sizeof(DWORD);
  has_pos = has_pos && (RegQueryValueExW(key, kRegValueHeight, nullptr, nullptr,
                                         reinterpret_cast<BYTE*>(&h), &size) == ERROR_SUCCESS);

  RegCloseKey(key);

  if (has_pos && w >= 600 && h >= 400) {
    out_rect.left = x;
    out_rect.top = y;
    out_rect.right = x + w;
    out_rect.bottom = y + h;

    HMONITOR hMon = MonitorFromRect(&out_rect, MONITOR_DEFAULTTONULL);
    if (hMon != nullptr) {
      return true;
    }
  }

  return out_is_maximized;
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  RECT saved_rect{};
  bool saved_is_max = false;
  bool has_saved_state = ReadSavedWindowState(saved_rect, saved_is_max);

  int window_x, window_y, window_w, window_h;

  if (has_saved_state && (saved_rect.right > saved_rect.left)) {
    window_x = saved_rect.left;
    window_y = saved_rect.top;
    window_w = saved_rect.right - saved_rect.left;
    window_h = saved_rect.bottom - saved_rect.top;
  } else {
    const POINT target_point = {static_cast<LONG>(origin.x),
                                static_cast<LONG>(origin.y)};
    HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
    UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
    double scale_factor = dpi / 96.0;

    window_x = Scale(origin.x, scale_factor);
    window_y = Scale(origin.y, scale_factor);
    window_w = Scale(size.width, scale_factor);
    window_h = Scale(size.height, scale_factor);
  }

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      window_x, window_y, window_w, window_h,
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  RECT saved_rect{};
  bool saved_is_max = false;
  if (ReadSavedWindowState(saved_rect, saved_is_max)) {
    if (saved_is_max) {
      return ShowWindow(window_handle_, SW_MAXIMIZE);
    } else {
      return ShowWindow(window_handle_, SW_NORMAL);
    }
  }
  // Se não houver informação salva (primeira execução), abre maximizado:
  return ShowWindow(window_handle_, SW_MAXIMIZE);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_EXITSIZEMOVE:
      SaveWindowState(hwnd);
      break;

    case WM_SYSCOMMAND:
      if ((wparam & 0xFFF0) == SC_MAXIMIZE || (wparam & 0xFFF0) == SC_RESTORE) {
        LRESULT res = DefWindowProc(hwnd, message, wparam, lparam);
        SaveWindowState(hwnd);
        return res;
      }
      break;

    case WM_CLOSE:
      SaveWindowState(hwnd);
      break;

    case WM_DESTROY:
      SaveWindowState(hwnd);
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
