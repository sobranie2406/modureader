#include <cassert>
#include <chrono>
#include <future>
#include <vector>
#include "../../windows/onnx/serial_worker.h"

int main() {
  using namespace std::chrono_literals;
  const auto ui = std::this_thread::get_id();
  std::promise<void> started, release, replied;
  auto released = release.get_future().share();
  std::atomic<int> wakes{0};
  std::vector<int> order;
  modu::SerialWorker worker([&] { ++wakes; });
  assert(worker.Post([&] {
    assert(std::this_thread::get_id() != ui);
    order.push_back(1); // load
    started.set_value();
    released.wait(); // Stand-in for native inference, held deliberately.
    order.push_back(2); // inference finished
    return [&] {
      assert(std::this_thread::get_id() == ui);
      replied.set_value();
    };
  }));
  assert(started.get_future().wait_for(2s) == std::future_status::ready);
  // The owner/UI can keep processing events while inference is blocked.
  int inputEvents = 0;
  for (int i = 0; i < 100; ++i) { ++inputEvents; worker.Drain(); }
  assert(inputEvents == 100 && wakes == 0);
  assert(worker.Post([&] {
    order.push_back(3); // close cannot race inference
    return [] {};
  }));
  release.set_value();
  const auto deadline = std::chrono::steady_clock::now() + 2s;
  while (wakes < 2 && std::chrono::steady_clock::now() < deadline) std::this_thread::yield();
  assert(wakes == 2);
  worker.Drain();
  assert(replied.get_future().wait_for(0s) == std::future_status::ready);
  worker.Shutdown();
  assert((order == std::vector<int>{1, 2, 3}));
  assert(!worker.Post([] { return [] {}; }));

  // Shutdown joins an active inference, drops queued work and never invokes
  // platform replies after the owner has begun teardown.
  std::promise<void> active, unblock;
  auto gate = unblock.get_future().share();
  std::atomic<bool> queuedRan{false}, callbackRan{false};
  modu::SerialWorker closing([] {});
  closing.Post([&] {
    active.set_value(); gate.wait();
    return [&] { callbackRan = true; };
  });
  active.get_future().wait();
  closing.Post([&] { queuedRan = true; return [] {}; });
  std::thread releaseThread([&] {
    std::this_thread::sleep_for(30ms);
    unblock.set_value();
  });
  closing.Shutdown();
  releaseThread.join();
  closing.Drain();
  assert(!queuedRan && !callbackRan);
}
