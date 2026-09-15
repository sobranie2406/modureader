#pragma once
#include <windows.h>
#include <memory>
#include <stdexcept>
#include "serial_worker.h"

namespace modu {
class PlatformWorker {
 public:
  explicit PlatformWorker(std::function<void()> cleanup) {
    const auto instance = GetModuleHandle(nullptr);
    WNDCLASSW wc{};
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = instance;
    wc.lpszClassName = L"ModuOnnxReplyWindow";
    if (!RegisterClassW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      throw std::runtime_error("Cannot register inference reply window");
    }
    window_ = CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0,
                              HWND_MESSAGE, nullptr, instance, this);
    if (!window_) throw std::runtime_error("Cannot create inference reply window");
    worker_ = std::make_unique<SerialWorker>(
        [this] { PostMessageW(window_, kReply, 0, 0); },
        [] { SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL); },
        std::move(cleanup));
  }
  ~PlatformWorker() {
    worker_.reset(); // Join while window and plugin implementation still exist.
    DestroyWindow(window_);
  }
  bool Post(SerialWorker::Work work) { return worker_->Post(std::move(work)); }
 private:
  static constexpr UINT kReply = WM_APP + 0x4D5;
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM w, LPARAM l) {
    if (message == WM_NCCREATE) {
      auto create = reinterpret_cast<CREATESTRUCTW*>(l);
      SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                       reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    auto self = reinterpret_cast<PlatformWorker*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == kReply && self && self->worker_) {
      self->worker_->Drain();
      return 0;
    }
    return DefWindowProcW(hwnd, message, w, l);
  }
  HWND window_ = nullptr;
  std::unique_ptr<SerialWorker> worker_;
};
} // namespace modu
