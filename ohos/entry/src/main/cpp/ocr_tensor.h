#ifndef MODU_OCR_TENSOR_H
#define MODU_OCR_TENSOR_H

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

namespace modu {
constexpr size_t kMaxOcrInputElements = 3 * 1024 * 1024;
constexpr size_t kMaxOcrOutputElements = 6000000;

inline size_t OcrElementCount(const std::vector<int64_t> &shape, size_t limit) {
  if (shape.empty() || shape.size() > 4) throw std::invalid_argument("Invalid OCR shape");
  size_t count = 1;
  for (int64_t axis : shape) {
    if (axis <= 0 || static_cast<uint64_t>(axis) > limit / count) {
      throw std::invalid_argument("Invalid OCR shape");
    }
    count *= static_cast<size_t>(axis);
  }
  return count;
}

inline size_t OcrFloatCount(size_t bytes, const std::vector<int64_t> &shape) {
  const size_t count = OcrElementCount(shape, kMaxOcrInputElements);
  if (bytes != count * sizeof(float)) throw std::invalid_argument("Invalid OCR byte count");
  return count;
}

inline void ValidateOcrInput(const std::string &name, const std::vector<float> &values,
                             const std::vector<int64_t> &shape) {
  if ((name != "det" && name != "rec") || shape.size() != 4 || shape[0] != 1 || shape[1] != 3 ||
      values.size() != OcrElementCount(shape, kMaxOcrInputElements)) {
    throw std::invalid_argument("Invalid OCR input");
  }
  for (float value : values) {
    if (!std::isfinite(value)) throw std::invalid_argument("Invalid OCR input");
  }
}

inline void ValidateOcrOutput(size_t count, const std::vector<int64_t> &shape) {
  if (count != OcrElementCount(shape, kMaxOcrOutputElements)) {
    throw std::invalid_argument("Invalid OCR output");
  }
}

struct OcrTensor {
  std::vector<float> data;
  std::vector<int64_t> shape;
};
}  // namespace modu
#endif
