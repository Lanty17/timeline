#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <flutter/standard_method_codec.h>
#include <cstdio>
#include <memory>
#include <optional>
#include <string>
#include <windows.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Custom channel: moves the window by drag deltas coming from Flutter.
  flutter::MethodChannel<flutter::EncodableValue> moveChannel(
      flutter_controller_->engine()->messenger(), "timeline/move_window",
      &flutter::StandardMethodCodec::GetInstance());
  moveChannel.SetMethodCallHandler(
      [this, hwnd = GetHandle()](const flutter::MethodCall<>& call,
                           std::unique_ptr<flutter::MethodResult<>> result) {
        if (call.method_name() == "move") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          double dx = 0, dy = 0;
          auto readNum = [](const flutter::EncodableValue* v) -> double {
            if (v == nullptr) return 0.0;
            if (const auto* d = std::get_if<double>(v)) return *d;
            if (const auto* i = std::get_if<int32_t>(v)) return static_cast<double>(*i);
            if (const auto* l = std::get_if<int64_t>(v)) return static_cast<double>(*l);
            return 0.0;
          };
          if (args != nullptr) {
            const auto dxIt = args->find(flutter::EncodableValue("dx"));
            const auto dyIt = args->find(flutter::EncodableValue("dy"));
            if (dxIt != args->end()) dx = readNum(&dxIt->second);
            if (dyIt != args->end()) dy = readNum(&dyIt->second);
          }
          RECT r;
          if (GetWindowRect(hwnd, &r)) {
            auto nx = r.left + static_cast<LONG>(dx);
            auto ny = r.top + static_cast<LONG>(dy);
            MoveWindow(hwnd, nx, ny, r.right - r.left, r.bottom - r.top, TRUE);
          }
          result->Success();
        } else if (call.method_name() == "startDrag") {
          // Delegate dragging to the native system move loop (same as
          // window_manager). The OS handles all subsequent mouse moves so the
          // window moves smoothly without per-frame MoveWindow flicker.
          ReleaseCapture();
          SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
        } else if (call.method_name() == "set_topmost") {
          const auto* b = std::get_if<bool>(call.arguments());
          if (b != nullptr) {
            HWND pos = *b ? HWND_TOPMOST : HWND_NOTOPMOST;
            SetWindowPos(hwnd, pos, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
          }
          result->Success();
        } else if (call.method_name() == "set_draggable") {
          const auto* b = std::get_if<bool>(call.arguments());
          if (b != nullptr) drag_enabled_ = *b;
          result->Success();
        } else if (call.method_name() == "ping") {
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Window dragging is driven from Flutter (Listener per-frame MoveWindow).
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_EXITSIZEMOVE: {
      RECT r;
      if (GetWindowRect(hwnd, &r)) {
        char buf[32];
        sprintf_s(buf, sizeof(buf), "%dx%d", r.right - r.left, r.bottom - r.top);
        FILE* fp = nullptr;
        if (fopen_s(&fp, "D:\\Downloads\\timeline\\size.txt", "w") == 0) {
          fputs(buf, fp);
          fclose(fp);
        }
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
