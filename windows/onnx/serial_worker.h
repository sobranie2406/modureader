#pragma once

#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

namespace modu {
// Jobs execute serially; replies execute only when the owner calls Drain().
// Shutdown joins the active job before releasing queued replies on the owner.
class SerialWorker {
 public:
  using Reply = std::function<void()>;
  using Work = std::function<Reply()>;
  explicit SerialWorker(std::function<void()> wake,
                        std::function<void()> initialize = [] {},
                        std::function<void()> cleanup = [] {})
      : wake_(std::move(wake)), thread_([this, initialize, cleanup] {
          initialize();
          Run();
          cleanup();
        }) {}
  ~SerialWorker() { Shutdown(); }
  bool Post(Work work) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stopping_) return false;
    jobs_.push_back(std::move(work));
    ready_.notify_one();
    return true;
  }
  void Drain() {
    std::deque<Reply> replies;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      replies.swap(replies_);
    }
    for (auto& reply : replies) reply();
  }
  void Shutdown() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      stopping_ = true;
      jobs_.clear();
    }
    ready_.notify_one();
    if (thread_.joinable()) thread_.join();
    // No Flutter callbacks after shutdown. Captures are released on the owner.
    replies_.clear();
  }
 private:
  void Run() {
    for (;;) {
      Work work;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        ready_.wait(lock, [this] { return stopping_ || !jobs_.empty(); });
        if (stopping_) return;
        work = std::move(jobs_.front());
        jobs_.pop_front();
      }
      auto reply = work(); // Adapter must convert exceptions to error replies.
      {
        std::lock_guard<std::mutex> lock(mutex_);
        replies_.push_back(std::move(reply));
      }
      wake_();
    }
  }
  std::function<void()> wake_;
  std::mutex mutex_;
  std::condition_variable ready_;
  std::deque<Work> jobs_;
  std::deque<Reply> replies_;
  bool stopping_ = false;
  std::thread thread_;
};
} // namespace modu
