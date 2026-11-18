#ifndef MODU_OCR_SESSION_H
#define MODU_OCR_SESSION_H

#include "ocr_tensor.h"
#include <onnxruntime_cxx_api.h>
#include <memory>

namespace modu {
class OcrSession {
 public:
  const char *Stage() const { return stage_; }

  void Close() {
    detection_.reset();
    recognition_.reset();
    detection_input_.clear();
    detection_output_.clear();
    recognition_input_.clear();
    recognition_output_.clear();
  }

  void Load(const std::string &directory) {
    Close();
    stage_ = "LOAD_PATH";
    if (directory.empty() || directory[0] != '/' || directory.size() > 4096 ||
        directory.find('\0') != std::string::npos) {
      throw std::invalid_argument("Invalid OCR model directory");
    }
    if (!env_) {
      stage_ = "LOAD_ENV";
      env_ = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_FATAL, "modu_ocr",
          [](void *, OrtLoggingLevel, const char *, const char *, const char *, const char *) {}, nullptr);
    }
    Ort::SessionOptions options;
    options.SetIntraOpNumThreads(2);
    options.SetInterOpNumThreads(1);
    options.SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
    options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_BASIC);
    options.DisableCpuMemArena();
    options.DisableMemPattern();
    Ort::AllocatorWithDefaultOptions allocator;
    try {
      stage_ = "LOAD_DET";
      detection_ = std::make_unique<Ort::Session>(*env_, (directory + "/det.onnx").c_str(), options);
      stage_ = "LOAD_REC";
      recognition_ = std::make_unique<Ort::Session>(*env_, (directory + "/rec.onnx").c_str(), options);
      stage_ = "LOAD_SCHEMA";
      for (Ort::Session *session : {detection_.get(), recognition_.get()}) {
        if (session->GetInputCount() != 1 || session->GetOutputCount() == 0) {
          throw std::invalid_argument("Invalid OCR model");
        }
      }
      detection_input_ = detection_->GetInputNameAllocated(0, allocator).get();
      detection_output_ = detection_->GetOutputNameAllocated(0, allocator).get();
      recognition_input_ = recognition_->GetInputNameAllocated(0, allocator).get();
      recognition_output_ = recognition_->GetOutputNameAllocated(0, allocator).get();
    } catch (...) {
      Close();
      throw;
    }
  }

  OcrTensor Run(const std::string &name, std::vector<float> &data,
                 const std::vector<int64_t> &shape) {
    stage_ = "RUN_INPUT";
    ValidateOcrInput(name, data, shape);
    Ort::Session *session = name == "det" ? detection_.get() : recognition_.get();
    if (!session) throw std::invalid_argument("OCR model is not loaded");
    const char *input_name = (name == "det" ? detection_input_ : recognition_input_).c_str();
    const char *output_name = (name == "det" ? detection_output_ : recognition_output_).c_str();
    auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    auto input = Ort::Value::CreateTensor<float>(memory, data.data(), data.size(), shape.data(), shape.size());
    stage_ = name == "det" ? "RUN_DET" : "RUN_REC";
    auto outputs = session->Run(Ort::RunOptions{nullptr}, &input_name, &input, 1, &output_name, 1);
    stage_ = "RUN_OUTPUT";
    if (outputs.size() != 1 || !outputs[0].IsTensor()) throw std::invalid_argument("Invalid OCR output");
    auto info = outputs[0].GetTensorTypeAndShapeInfo();
    if (info.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
      throw std::invalid_argument("Invalid OCR output type");
    }
    OcrTensor result;
    result.shape = info.GetShape();
    const size_t count = info.GetElementCount();
    ValidateOcrOutput(count, result.shape);
    const float *values = outputs[0].GetTensorData<float>();
    for (size_t i = 0; i < count; ++i) {
      if (!std::isfinite(values[i])) throw std::invalid_argument("Invalid OCR output values");
    }
    result.data.assign(values, values + count);
    return result;
  }

 private:
  std::unique_ptr<Ort::Env> env_;
  std::unique_ptr<Ort::Session> detection_, recognition_;
  std::string detection_input_, detection_output_, recognition_input_, recognition_output_;
  const char *stage_ = "NONE";
};
}  // namespace modu
#endif
