#include "embedding_session.h"
#include "ocr_session.h"
#include <napi/native_api.h>
#include <atomic>
#include <cstring>
#include <mutex>

namespace {
struct State {
  std::mutex mutex;
  std::atomic<bool> disposed{false};
  modu::EmbeddingSession session;
  modu::OcrSession ocr;
};
using StateRef = std::shared_ptr<State>;
enum class Operation { Load, Embed, Close, OcrLoad, OcrRun, OcrClose };
bool IsOcr(Operation operation) {
  return operation == Operation::OcrLoad || operation == Operation::OcrRun || operation == Operation::OcrClose;
}
struct Job {
  StateRef state;
  Operation operation;
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
  std::string path;
  std::vector<int64_t> ids;
  int dimensions = 0;
  std::vector<double> output;
  std::string tensor_name;
  std::vector<float> tensor_data;
  std::vector<int64_t> tensor_shape;
  modu::OcrTensor tensor_output;
  bool failed = false;
  bool memory = false;
  const char *failure_stage = "NONE";
  int ort_error = -1;
};

void Execute(napi_env, void *data) {
  auto &job = *static_cast<Job *>(data);
  std::lock_guard<std::mutex> guard(job.state->mutex);
  try {
    if (job.state->disposed.load()) throw std::runtime_error("Detached");
    switch (job.operation) {
      case Operation::Load: job.state->session.Load(job.path); break;
      case Operation::Embed: job.output = job.state->session.Embed(job.ids, job.dimensions); break;
      case Operation::Close: job.state->session.Close(); break;
      case Operation::OcrLoad: job.state->ocr.Load(job.path); break;
      case Operation::OcrRun: job.tensor_output = job.state->ocr.Run(job.tensor_name, job.tensor_data, job.tensor_shape); break;
      case Operation::OcrClose: job.state->ocr.Close(); break;
    }
  } catch (const Ort::Exception &error) {
    job.failed = true;
    job.ort_error = static_cast<int>(error.GetOrtErrorCode());
    job.failure_stage = IsOcr(job.operation) ? job.state->ocr.Stage() : "NONE";
    if (IsOcr(job.operation)) job.state->ocr.Close(); else job.state->session.Close();
  } catch (const std::bad_alloc &) {
    job.failed = job.memory = true;
    if (IsOcr(job.operation)) job.state->ocr.Close(); else job.state->session.Close();
  } catch (...) {
    job.failed = true;
    job.failure_stage = IsOcr(job.operation) ? job.state->ocr.Stage() : "NONE";
    if (IsOcr(job.operation)) job.state->ocr.Close(); else job.state->session.Close();
  }
}

bool OcrResult(napi_env env, const modu::OcrTensor &tensor, napi_value *result) {
  napi_value buffer, shape;
  void *values = nullptr;
  if (napi_create_arraybuffer(env, tensor.data.size() * sizeof(float), &values, &buffer) != napi_ok ||
      napi_create_array_with_length(env, tensor.shape.size(), &shape) != napi_ok ||
      napi_create_object(env, result) != napi_ok) return false;
  std::memcpy(values, tensor.data.data(), tensor.data.size() * sizeof(float));
  for (size_t i = 0; i < tensor.shape.size(); ++i) {
    napi_value axis;
    if (napi_create_int64(env, tensor.shape[i], &axis) != napi_ok ||
        napi_set_element(env, shape, i, axis) != napi_ok) return false;
  }
  return napi_set_named_property(env, *result, "data", buffer) == napi_ok &&
      napi_set_named_property(env, *result, "shape", shape) == napi_ok;
}

void Complete(napi_env env, napi_status status, void *data) {
  std::unique_ptr<Job> job(static_cast<Job *>(data));
  napi_value value = nullptr;
  if (status == napi_ok && !job->failed && !job->state->disposed.load() && job->operation == Operation::OcrRun &&
      !OcrResult(env, job->tensor_output, &value)) job->failed = job->memory = true;
  if (status != napi_ok || job->failed || job->state->disposed.load()) {
    napi_value code, message;
    const char *code_text = IsOcr(job->operation) ? (job->memory ? "OCR_MEMORY" : "OCR_FAILED")
        : (job->memory ? "LOCAL_EMBEDDING_MEMORY" : "LOCAL_EMBEDDING_FAILED");
    std::string diagnostic;
    if (IsOcr(job->operation) && !job->memory) {
      diagnostic = std::string(code_text) + "_" + job->failure_stage;
      if (job->ort_error >= 0) diagnostic += "_ORT_" + std::to_string(job->ort_error);
      code_text = diagnostic.c_str();
    }
    napi_create_string_utf8(env, code_text,
                            NAPI_AUTO_LENGTH, &code);
    napi_create_string_utf8(env, IsOcr(job->operation) ? "Local OCR failed. Please retry."
        : "Local embedding failed. Please retry.", NAPI_AUTO_LENGTH, &message);
    napi_create_error(env, code, message, &value);
    napi_reject_deferred(env, job->deferred, value);
  } else {
    if (job->operation == Operation::Embed) {
      napi_create_array_with_length(env, job->output.size(), &value);
      for (size_t i = 0; i < job->output.size(); ++i) {
        napi_value item;
        napi_create_double(env, job->output[i], &item);
        napi_set_element(env, value, i, item);
      }
    } else if (job->operation != Operation::OcrRun) {
      napi_get_undefined(env, &value);
    }
    napi_resolve_deferred(env, job->deferred, value);
  }
  napi_delete_async_work(env, job->work);
}

napi_value Queue(napi_env env, napi_callback_info info, Operation operation) {
  size_t argc = 3;
  napi_value args[3];
  void *data = nullptr;
  if (napi_get_cb_info(env, info, &argc, args, nullptr, &data) != napi_ok || !data) return nullptr;
  auto job = std::make_unique<Job>();
  job->state = *static_cast<StateRef *>(data);
  job->operation = operation;
  bool valid = true;
  if (operation == Operation::Load || operation == Operation::OcrLoad) {
    size_t length = 0;
    valid = argc == 1 && napi_get_value_string_utf8(env, args[0], nullptr, 0, &length) == napi_ok &&
        length > 0 && length <= 4096;
    if (valid) {
      std::vector<char> path(length + 1);
      valid = napi_get_value_string_utf8(env, args[0], path.data(), path.size(), &length) == napi_ok;
      job->path.assign(path.data(), length);
    }
  } else if (operation == Operation::Embed) {
    napi_typedarray_type type;
    size_t length = 0, offset = 0;
    void *ids = nullptr;
    napi_value buffer;
    valid = argc == 2 && napi_get_typedarray_info(env, args[0], &type, &length, &ids, &buffer, &offset) == napi_ok &&
        type == napi_bigint64_array && length > 0 && length <= 512 && ids &&
        napi_get_value_int32(env, args[1], &job->dimensions) == napi_ok &&
        (job->dimensions == 384 || job->dimensions == 512);
    if (valid) job->ids.assign(static_cast<int64_t *>(ids), static_cast<int64_t *>(ids) + length);
  } else if (operation == Operation::OcrRun) {
    napi_typedarray_type type;
    size_t length = 0, offset = 0, name_length = 0;
    void *values = nullptr;
    void *backing = nullptr;
    size_t buffer_bytes = 0;
    napi_value buffer;
    uint32_t rank = 0;
    valid = argc == 3 &&
        napi_get_value_string_utf8(env, args[0], nullptr, 0, &name_length) == napi_ok && name_length == 3 &&
        napi_get_typedarray_info(env, args[1], &type, &length, &values, &buffer, &offset) == napi_ok &&
        type == napi_uint8_array && length > 0 && length <= modu::kMaxOcrInputElements * sizeof(float) && values &&
        napi_get_arraybuffer_info(env, buffer, &backing, &buffer_bytes) == napi_ok && backing &&
        offset <= buffer_bytes && length <= buffer_bytes - offset &&
        values == static_cast<uint8_t *>(backing) + offset &&
        napi_get_array_length(env, args[2], &rank) == napi_ok && rank == 4;
    if (valid) {
      char name[4] = {};
      valid = napi_get_value_string_utf8(env, args[0], name, sizeof(name), &name_length) == napi_ok;
      job->tensor_name.assign(name, name_length);
      valid = valid && (job->tensor_name == "det" || job->tensor_name == "rec");
      for (uint32_t i = 0; valid && i < rank; ++i) {
        napi_value axis;
        double number = 0;
        valid = napi_get_element(env, args[2], i, &axis) == napi_ok &&
            napi_get_value_double(env, axis, &number) == napi_ok && std::isfinite(number) &&
            number >= 1 && number <= modu::kMaxOcrInputElements && std::floor(number) == number;
        if (valid) job->tensor_shape.push_back(static_cast<int64_t>(number));
      }
      if (valid) {
        const size_t count = modu::OcrFloatCount(length, job->tensor_shape);
        job->tensor_data.resize(count);
        std::memcpy(job->tensor_data.data(), values, length);
      }
    }
  }
  if (!valid) {
    napi_throw_type_error(env, IsOcr(operation) ? "INVALID_OCR_INPUT" : "INVALID_EMBEDDING_INPUT",
                          IsOcr(operation) ? "Invalid local OCR input" : "Invalid local embedding input");
    return nullptr;
  }
  napi_value promise, name;
  if (napi_create_promise(env, &job->deferred, &promise) != napi_ok ||
      napi_create_string_utf8(env, IsOcr(operation) ? "ModuLocalOcr" : "ModuLocalEmbedding", NAPI_AUTO_LENGTH, &name) != napi_ok ||
      napi_create_async_work(env, nullptr, name, Execute, Complete, job.get(), &job->work) != napi_ok ||
      napi_queue_async_work(env, job->work) != napi_ok) {
    if (job->work) napi_delete_async_work(env, job->work);
    napi_throw_error(env, IsOcr(operation) ? "OCR_FAILED" : "LOCAL_EMBEDDING_FAILED",
                     IsOcr(operation) ? "Could not schedule local OCR" : "Could not schedule local embedding");
    return nullptr;
  }
  job.release();
  return promise;
}
napi_value SafeQueue(napi_env env, napi_callback_info info, Operation operation) {
  try { return Queue(env, info, operation); }
  catch (...) {
    napi_throw_error(env, IsOcr(operation) ? "OCR_FAILED" : "LOCAL_EMBEDDING_FAILED",
                     IsOcr(operation) ? "Could not schedule local OCR" : "Could not schedule local embedding");
    return nullptr;
  }
}
napi_value Load(napi_env env, napi_callback_info info) { return SafeQueue(env, info, Operation::Load); }
napi_value Embed(napi_env env, napi_callback_info info) { return SafeQueue(env, info, Operation::Embed); }
napi_value Close(napi_env env, napi_callback_info info) { return SafeQueue(env, info, Operation::Close); }
napi_value OcrLoad(napi_env env, napi_callback_info info) { return SafeQueue(env, info, Operation::OcrLoad); }
napi_value OcrRun(napi_env env, napi_callback_info info) { return SafeQueue(env, info, Operation::OcrRun); }
napi_value OcrClose(napi_env env, napi_callback_info info) { return SafeQueue(env, info, Operation::OcrClose); }
napi_value Available(napi_env env, napi_callback_info) {
  napi_value result;
  const OrtApiBase *base = OrtGetApiBase();
  napi_get_boolean(env, base && base->GetApi(ORT_API_VERSION), &result);
  return result;
}
void Cleanup(void *data) {
  auto *state = static_cast<StateRef *>(data);
  (*state)->disposed.store(true);
  delete state;
}
napi_value Init(napi_env env, napi_value exports) {
  auto *state = new StateRef(std::make_shared<State>());
  napi_property_descriptor properties[] = {
      {"load", nullptr, Load, nullptr, nullptr, nullptr, napi_default, state},
      {"embed", nullptr, Embed, nullptr, nullptr, nullptr, napi_default, state},
      {"close", nullptr, Close, nullptr, nullptr, nullptr, napi_default, state},
      {"isAvailable", nullptr, Available, nullptr, nullptr, nullptr, napi_default, state},
      {"ocrLoad", nullptr, OcrLoad, nullptr, nullptr, nullptr, napi_default, state},
      {"ocrRun", nullptr, OcrRun, nullptr, nullptr, nullptr, napi_default, state},
      {"ocrClose", nullptr, OcrClose, nullptr, nullptr, nullptr, napi_default, state},
  };
  napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
  napi_add_env_cleanup_hook(env, Cleanup, state);
  return exports;
}
}  // namespace

static napi_module module = {1, 0, nullptr, Init, "modu_embedding", nullptr, {0}};
extern "C" __attribute__((constructor)) void RegisterModuEmbedding() { napi_module_register(&module); }
