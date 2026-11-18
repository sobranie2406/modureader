#include "embedding_math.h"
#include <cassert>
#include <limits>

template <typename F> void Rejects(F fn) {
  bool rejected = false;
  try { fn(); } catch (const std::invalid_argument &) { rejected = true; }
  assert(rejected);
}
int main() {
  for (size_t dimensions : {384, 512}) {
    std::vector<float> hidden(2 * dimensions, 0);
    hidden[0] = 6;
    hidden[dimensions + 1] = 8;
    const auto vector = modu::PoolEmbedding(hidden.data(), hidden.size(),
                                            {1, 2, static_cast<int64_t>(dimensions)}, 2, dimensions);
    assert(std::abs(vector[0] - 0.6) < 1e-12);
    assert(std::abs(vector[1] - 0.8) < 1e-12);
    assert(vector[dimensions - 1] == 0);
    std::vector<float> sentence(dimensions, 0);
    sentence[0] = 3;
    sentence[1] = 4;
    for (const auto &shape : {std::vector<int64_t>{1, static_cast<int64_t>(dimensions)},
                             std::vector<int64_t>{static_cast<int64_t>(dimensions)}}) {
      const auto result = modu::PoolEmbedding(sentence.data(), sentence.size(), shape, 2, dimensions);
      assert(std::abs(result[0] - 0.6) < 1e-12 && std::abs(result[1] - 0.8) < 1e-12);
    }
    Rejects([&] { modu::PoolEmbedding(hidden.data(), 1, {1, 2, static_cast<int64_t>(dimensions)}, 2, dimensions); });
    Rejects([&] { modu::PoolEmbedding(hidden.data(), hidden.size(), {2, static_cast<int64_t>(dimensions)}, 2, dimensions); });
    sentence[0] = std::numeric_limits<float>::quiet_NaN();
    Rejects([&] { modu::PoolEmbedding(sentence.data(), sentence.size(), {static_cast<int64_t>(dimensions)}, 2, dimensions); });
    sentence.assign(dimensions, 0);
    Rejects([&] { modu::PoolEmbedding(sentence.data(), sentence.size(), {static_cast<int64_t>(dimensions)}, 2, dimensions); });
  }
  std::vector<float> invalid(384, 1);
  Rejects([&] { modu::PoolEmbedding(invalid.data(), invalid.size(), {384}, 513, 384); });
  Rejects([&] { modu::PoolEmbedding(invalid.data(), invalid.size(), {384}, 1, 383); });
  Rejects([&] { modu::PoolEmbedding(nullptr, 384, {384}, 1, 384); });
}
