#ifndef MODU_EMBEDDING_SESSION_H
#define MODU_EMBEDDING_SESSION_H

#include "embedding_math.h"
#include <onnxruntime_cxx_api.h>
#include <algorithm>
#include <memory>
#include <string>
#include <unordered_set>

namespace modu {
class EmbeddingSession {
 public:
  void Close() { session_.reset(); output_.clear(); inputs_.clear(); }

  void Load(const std::string &path) {
    Close();
    if (path.empty() || path[0] != '/' || path.size() > 4096 || path.find('\0') != std::string::npos) {
      throw std::invalid_argument("Invalid model path");
    }
    if (!env_) {
      // Do not send model paths, runtime diagnostics or book data to system logs.
      env_ = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_FATAL, "modu_embedding",
          [](void *, OrtLoggingLevel, const char *, const char *, const char *, const char *) {}, nullptr);
    }
    Ort::SessionOptions options;
    options.SetIntraOpNumThreads(1);
    options.SetInterOpNumThreads(1);
    options.SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
    options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_BASIC);
    options.DisableCpuMemArena();
    options.DisableMemPattern();
    session_ = std::make_unique<Ort::Session>(*env_, path.c_str(), options);
    Ort::AllocatorWithDefaultOptions allocator;
    for (size_t i = 0; i < session_->GetInputCount(); ++i) {
      auto name = session_->GetInputNameAllocated(i, allocator);
      inputs_.insert(name.get());
    }
    if (!inputs_.count("input_ids") || inputs_.size() > 3) {
      throw std::invalid_argument("Invalid model inputs");
    }
    for (const auto &name : inputs_) {
      if (name != "input_ids" && name != "attention_mask" && name != "token_type_ids") {
        throw std::invalid_argument("Invalid model inputs");
      }
    }
    std::vector<std::string> outputs;
    for (size_t i = 0; i < session_->GetOutputCount(); ++i) {
      auto name = session_->GetOutputNameAllocated(i, allocator);
      outputs.emplace_back(name.get());
    }
    if (outputs.empty()) throw std::invalid_argument("Missing model output");
    output_ = outputs.front();
    for (const char *preferred : {"last_hidden_state", "sentence_embedding"}) {
      if (std::find(outputs.begin(), outputs.end(), preferred) != outputs.end()) output_ = preferred;
    }
  }

  std::vector<double> Embed(std::vector<int64_t> &ids, int dimensions) {
    if (!session_ || ids.empty() || ids.size() > 512 ||
        (dimensions != 384 && dimensions != 512) ||
        std::any_of(ids.begin(), ids.end(), [](int64_t id) { return id < 0; })) {
      throw std::invalid_argument("Invalid embedding input");
    }
    const int64_t shape[] = {1, static_cast<int64_t>(ids.size())};
    auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    std::vector<int64_t> mask(ids.size(), 1), types(ids.size(), 0);
    std::vector<const char *> names{"input_ids"};
    std::vector<Ort::Value> tensors;
    tensors.push_back(Ort::Value::CreateTensor<int64_t>(memory, ids.data(), ids.size(), shape, 2));
    if (inputs_.count("attention_mask")) {
      names.push_back("attention_mask");
      tensors.push_back(Ort::Value::CreateTensor<int64_t>(memory, mask.data(), mask.size(), shape, 2));
    }
    if (inputs_.count("token_type_ids")) {
      names.push_back("token_type_ids");
      tensors.push_back(Ort::Value::CreateTensor<int64_t>(memory, types.data(), types.size(), shape, 2));
    }
    const char *output_name = output_.c_str();
    auto outputs = session_->Run(Ort::RunOptions{nullptr}, names.data(), tensors.data(), tensors.size(),
                                 &output_name, 1);
    if (outputs.size() != 1 || !outputs[0].IsTensor()) throw std::invalid_argument("Invalid model output");
    auto info = outputs[0].GetTensorTypeAndShapeInfo();
    if (info.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
      throw std::invalid_argument("Invalid output type");
    }
    return PoolEmbedding(outputs[0].GetTensorData<float>(), info.GetElementCount(), info.GetShape(),
                         ids.size(), static_cast<size_t>(dimensions));
  }

 private:
  std::unique_ptr<Ort::Env> env_;
  std::unique_ptr<Ort::Session> session_;
  std::unordered_set<std::string> inputs_;
  std::string output_;
};
}  // namespace modu
#endif
