#include "embedding_session.h"
#include <napi/native_api.h>
#include <atomic>
#include <mutex>

namespace {
struct State {
  std::mutex mutex;
  std::atomic<bool> disposed{false};
  modu::EmbeddingSession session;
};
using StateRef = std::shared_ptr<State>;
enum class Operation { Load, Embed, Close };
struct Job {
  StateRef state;
  Operation operation;
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
  std::string path;
  std::vector<int64_t> ids;
  int dimensions = 0;
  std::vector<double> output;
  bool failed = false;
  bool memory = false;
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
    }
  } catch (const std::bad_alloc &) {
    job.failed = job.memory = true;
    job.state->session.Close();
  } catch (...) {
    job.failed = true;
    job.state->session.Close();
  }
}

void Complete(napi_env env, napi_status status, void *data) {
  std::unique_ptr<Job> job(static_cast<Job *>(data));
  napi_value value = nullptr;
  if (status != napi_ok || job->failed || job->state->disposed.load()) {
    napi_value code, message;
    napi_create_string_utf8(env, job->memory ? "LOCAL_EMBEDDING_MEMORY" : "LOCAL_EMBEDDING_FAILED",
                            NAPI_AUTO_LENGTH, &code);
    napi_create_string_utf8(env, "Local embedding failed. Please retry.", NAPI_AUTO_LENGTH, &message);
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
    } else {
      napi_get_undefined(env, &value);
    }
    napi_resolve_deferred(env, job->deferred, value);
  }
  napi_delete_async_work(env, job->work);
}

napi_value Queue(napi_env env, napi_callback_info info, Operation operation) {
  size_t argc = 2;
  napi_value args[2];
  void *data = nullptr;
  if (napi_get_cb_info(env, info, &argc, args, nullptr, &data) != napi_ok || !data) return nullptr;
  auto job = std::make_unique<Job>();
  job->state = *static_cast<StateRef *>(data);
  job->operation = operation;
  bool valid = true;
  if (operation == Operation::Load) {
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
  }
  if (!valid) {
    napi_throw_type_error(env, "INVALID_EMBEDDING_INPUT", "Invalid local embedding input");
    return nullptr;
  }
  napi_value promise, name;
  if (napi_create_promise(env, &job->deferred, &promise) != napi_ok ||
      napi_create_string_utf8(env, "ModuLocalEmbedding", NAPI_AUTO_LENGTH, &name) != napi_ok ||
      napi_create_async_work(env, nullptr, name, Execute, Complete, job.get(), &job->work) != napi_ok ||
      napi_queue_async_work(env, job->work) != napi_ok) {
    if (job->work) napi_delete_async_work(env, job->work);
    napi_throw_error(env, "LOCAL_EMBEDDING_FAILED", "Could not schedule local embedding");
    return nullptr;
  }
  job.release();
  return promise;
}
napi_value SafeQueue(napi_env env, napi_callback_info info, Operation operation) {
  try { return Queue(env, info, operation); }
  catch (...) {
    napi_throw_error(env, "LOCAL_EMBEDDING_FAILED", "Could not schedule local embedding");
    return nullptr;
  }
}
napi_value Load(napi_env env, napi_callback_info info) { return SafeQueue(env, info, Operation::Load); }
napi_value Embed(napi_env env, napi_callback_info info) { return SafeQueue(env, info, Operation::Embed); }
napi_value Close(napi_env env, napi_callback_info info) { return SafeQueue(env, info, Operation::Close); }
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
  };
  napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
  napi_add_env_cleanup_hook(env, Cleanup, state);
  return exports;
}
}  // namespace

static napi_module module = {1, 0, nullptr, Init, "modu_embedding", nullptr, {0}};
extern "C" __attribute__((constructor)) void RegisterModuEmbedding() { napi_module_register(&module); }
