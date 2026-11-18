#include "ocr_tensor.h"
#include <cassert>
#include <limits>

template <typename F> void Rejects(F fn) {
  bool rejected = false;
  try { fn(); } catch (const std::invalid_argument &) { rejected = true; }
  assert(rejected);
}
int main() {
  assert(modu::OcrFloatCount(4423680, {1, 3, 480, 768}) == 1105920);
  assert(modu::OcrFloatCount(7741440, {1, 3, 960, 672}) == 1935360);
  Rejects([&] { modu::OcrFloatCount(1105920, {1, 3, 480, 768}); });
  Rejects([&] { modu::OcrFloatCount(4423681, {1, 3, 480, 768}); });
  Rejects([&] { modu::OcrFloatCount(3 * 1024 * 1024 * sizeof(float) + 4, {1, 3, 1024, 1024}); });
  for (const auto &shape : {std::vector<int64_t>{1, 3, 32, 32},
                           std::vector<int64_t>{1, 3, 1024, 1024},
                           std::vector<int64_t>{1, 3, 48, 1068}}) {
    std::vector<float> values(modu::OcrElementCount(shape, modu::kMaxOcrInputElements), 0.5f);
    modu::ValidateOcrInput("det", values, shape);
    modu::ValidateOcrInput("rec", values, shape);
  }
  std::vector<float> values(3 * 32 * 32, 0);
  const std::vector<int64_t> shape{1, 3, 32, 32};
  Rejects([&] { modu::ValidateOcrInput("other", values, shape); });
  Rejects([&] { modu::ValidateOcrInput("det", values, {2, 3, 32, 32}); });
  Rejects([&] { modu::ValidateOcrInput("det", values, {1, 3, 32, 31}); });
  Rejects([&] { modu::ValidateOcrInput("det", values, {1, 3, -1, 32}); });
  Rejects([&] { modu::ValidateOcrInput("det", values, {1, 3, 0, 32}); });
  Rejects([&] { modu::OcrElementCount({1, 3, std::numeric_limits<int64_t>::max(), 3}, modu::kMaxOcrInputElements); });
  values[0] = std::numeric_limits<float>::infinity();
  Rejects([&] { modu::ValidateOcrInput("det", values, shape); });
  values[0] = std::numeric_limits<float>::quiet_NaN();
  Rejects([&] { modu::ValidateOcrInput("rec", values, shape); });
  modu::ValidateOcrOutput(960 * 960, {1, 1, 960, 960});
  modu::ValidateOcrOutput(267 * 18710, {1, 267, 18710});
  modu::ValidateOcrOutput(267 * 18385, {1, 267, 18385});
  Rejects([&] { modu::ValidateOcrOutput(1, {1, 1, 960, 960}); });
  Rejects([&] { modu::ValidateOcrOutput(384 * 18710, {1, 384, 18710}); });
  Rejects([&] { modu::ValidateOcrOutput(0, {1, 0, 18710}); });
}
