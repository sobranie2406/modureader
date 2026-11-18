#ifndef MODU_EMBEDDING_MATH_H
#define MODU_EMBEDDING_MATH_H

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <vector>

namespace modu {
inline std::vector<double> PoolEmbedding(const float *values, size_t count,
                                        const std::vector<int64_t> &shape,
                                        size_t tokens, size_t dimensions) {
  size_t rows = 0;
  if (shape == std::vector<int64_t>{1, static_cast<int64_t>(tokens),
                                   static_cast<int64_t>(dimensions)}) {
    rows = tokens;
  } else if (shape == std::vector<int64_t>{1, static_cast<int64_t>(dimensions)} ||
             shape == std::vector<int64_t>{static_cast<int64_t>(dimensions)}) {
    rows = 1;
  }
  if (!values || !rows || !tokens || tokens > 512 || (dimensions != 384 && dimensions != 512) ||
      count != rows * dimensions) {
    throw std::invalid_argument("Invalid embedding shape");
  }
  std::vector<double> result(dimensions, 0);
  for (size_t row = 0; row < rows; ++row) {
    for (size_t i = 0; i < dimensions; ++i) result[i] += values[row * dimensions + i];
  }
  double squared_norm = 0;
  for (double &value : result) {
    value /= static_cast<double>(rows);
    squared_norm += value * value;
  }
  const double norm = std::sqrt(squared_norm);
  if (!std::isfinite(norm) || norm == 0) throw std::invalid_argument("Invalid embedding values");
  for (double &value : result) value /= norm;
  return result;
}
}  // namespace modu
#endif
