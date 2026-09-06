#include "native_crash_recorder.h"

#include <windows.h>
#include <dbghelp.h>
#include <shlobj.h>
#include <cstdio>
#include <cstring>

namespace {
HANDLE record_file = INVALID_HANDLE_VALUE;
LPTOP_LEVEL_EXCEPTION_FILTER previous_filter = nullptr;
volatile LONG recording = 0;
wchar_t previous_path[MAX_PATH] = {};

void WriteLine(const char* line) {
  if (record_file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  WriteFile(record_file, line, static_cast<DWORD>(strlen(line)), &written, nullptr);
}

// No arbitrary module paths/names, exception messages, registers or stack memory
// are persisted. DbgHelp is used for unwinding only, not symbol server lookup.
const char* PublicModule(HMODULE module) {
  wchar_t path[MAX_PATH] = {};
  if (!GetModuleFileNameW(module, path, MAX_PATH)) return "omitted";
  const wchar_t* name = wcsrchr(path, L'\\');
  name = name ? name + 1 : path;
  struct Library { const wchar_t* wide; const char* narrow; };
  static const Library allowed[] = {
    {L"modu.exe", "modu.exe"}, {L"flutter_windows.dll", "flutter_windows.dll"},
    {L"onnxruntime.dll", "onnxruntime.dll"}, {L"tokenizers_ffi.dll", "tokenizers_ffi.dll"},
    {L"ntdll.dll", "ntdll.dll"}, {L"kernel32.dll", "kernel32.dll"},
    {L"kernelbase.dll", "kernelbase.dll"}, {L"ucrtbase.dll", "ucrtbase.dll"},
    {L"vcruntime140.dll", "vcruntime140.dll"}, {L"vcruntime140_1.dll", "vcruntime140_1.dll"},
    {L"msvcp140.dll", "msvcp140.dll"}
  };
  for (const auto& entry : allowed) {
    if (_wcsicmp(entry.wide, name) == 0) return entry.narrow;
  }
  return "omitted";
}

DWORD64 CALLBACK ModuleBase(HANDLE process, DWORD64 address) {
  MEMORY_BASIC_INFORMATION memory = {};
  if (!VirtualQueryEx(process, reinterpret_cast<void*>(address), &memory, sizeof(memory)) ||
      memory.Type != MEM_IMAGE) return 0;
  return reinterpret_cast<DWORD64>(memory.AllocationBase);
}

PVOID CALLBACK FunctionTable(HANDLE, DWORD64 address) {
#if defined(_M_X64) || defined(_M_ARM64)
  DWORD64 base = 0;
  return RtlLookupFunctionEntry(address, &base, nullptr);
#else
  return nullptr;
#endif
}

void WriteFrame(HANDLE process, DWORD64 pc) {
  const DWORD64 base = ModuleBase(process, pc);
  if (!base || pc < base) return;  // Never persist absolute or unmapped addresses.
  IMAGE_DOS_HEADER dos = {};
  IMAGE_NT_HEADERS64 nt = {};
  SIZE_T read = 0;
  DWORD stamp = 0, image_size = 0;
  if (ReadProcessMemory(process, reinterpret_cast<void*>(base), &dos, sizeof(dos), &read) &&
      dos.e_magic == IMAGE_DOS_SIGNATURE && dos.e_lfanew > 0 && dos.e_lfanew < 1048576 &&
      ReadProcessMemory(process, reinterpret_cast<void*>(base + dos.e_lfanew), &nt, sizeof(nt), &read) &&
      nt.Signature == IMAGE_NT_SIGNATURE) {
    stamp = nt.FileHeader.TimeDateStamp;
    image_size = nt.OptionalHeader.SizeOfImage;
  }
  char line[160] = {};
  _snprintf_s(line, sizeof(line), _TRUNCATE, "frame=%s|%llx|%lx-%lx\n",
              PublicModule(reinterpret_cast<HMODULE>(base)),
              static_cast<unsigned long long>(pc - base), stamp, image_size);
  WriteLine(line);
}

void RecordException(EXCEPTION_POINTERS* exception) {
  FILETIME time = {};
  GetSystemTimeAsFileTime(&time);
  ULARGE_INTEGER ticks = {};
  ticks.LowPart = time.dwLowDateTime;
  ticks.HighPart = time.dwHighDateTime;
  const auto millis = (ticks.QuadPart - 116444736000000000ULL) / 10000ULL;
  char line[160] = {};
  _snprintf_s(line, sizeof(line), _TRUNCATE,
              "modu-native-v1\ncode=%lx\ntime=%llu\nbuild=%d\n",
              exception->ExceptionRecord->ExceptionCode, millis, FLUTTER_VERSION_BUILD);
  WriteLine(line);
  FlushFileBuffers(record_file);  // Keep reason even if unwinding fails later.
  CONTEXT context = *exception->ContextRecord;
  STACKFRAME64 stack = {};
  DWORD machine = 0;
#if defined(_M_X64)
  machine = IMAGE_FILE_MACHINE_AMD64;
  stack.AddrPC.Offset = context.Rip;
  stack.AddrFrame.Offset = context.Rbp;
  stack.AddrStack.Offset = context.Rsp;
#elif defined(_M_ARM64)
  machine = IMAGE_FILE_MACHINE_ARM64;
  stack.AddrPC.Offset = context.Pc;
  stack.AddrFrame.Offset = context.Fp;
  stack.AddrStack.Offset = context.Sp;
#else
  return;
#endif
  stack.AddrPC.Mode = stack.AddrFrame.Mode = stack.AddrStack.Mode = AddrModeFlat;
  HANDLE process = GetCurrentProcess();
  WriteFrame(process, stack.AddrPC.Offset);
  DWORD64 last = stack.AddrPC.Offset;
  DWORD64 last_sp = stack.AddrStack.Offset;
  for (int i = 1; i < 32; ++i) {
    if (!StackWalk64(machine, process, GetCurrentThread(), &stack, &context,
                     nullptr, FunctionTable, ModuleBase, nullptr) ||
        !stack.AddrPC.Offset) break;
    // Some unwinders return the seeded frame once before advancing.
    if (stack.AddrPC.Offset == last && stack.AddrStack.Offset == last_sp) {
      if (i == 1) continue;
      break;
    }
    WriteFrame(process, stack.AddrPC.Offset);
    last = stack.AddrPC.Offset;
    last_sp = stack.AddrStack.Offset;
  }
  FlushFileBuffers(record_file);
}

LONG WINAPI OnUnhandledException(EXCEPTION_POINTERS* exception) {
  // Only one DbgHelp caller, no allocating strings or application locks here.
  if (InterlockedCompareExchange(&recording, 1, 0) == 0 &&
      record_file != INVALID_HANDLE_VALUE && exception && exception->ContextRecord) {
    __try { RecordException(exception); }
    __except (EXCEPTION_EXECUTE_HANDLER) { /* Preserve the flushed header. */ }
  }
  // Do not swallow or "recover" a native crash; retain previous/OS behavior.
  return previous_filter ? previous_filter(exception) : EXCEPTION_CONTINUE_SEARCH;
}
}  // namespace

void InitializeNativeCrashRecorder() {
  if (record_file != INVALID_HANDLE_VALUE) return;
  PWSTR support = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &support))) return;
  std::wstring folder = std::wstring(support) + L"\\com.modu.reader";
  CoTaskMemFree(support);
  CreateDirectoryW(folder.c_str(), nullptr);
  folder += L"\\native-crash";
  CreateDirectoryW(folder.c_str(), nullptr);
  const std::wstring pending = folder + L"\\pending.txt";
  const std::wstring previous = folder + L"\\previous.txt";
  if (previous.size() >= MAX_PATH) return;
  wcscpy_s(previous_path, previous.c_str());
  // Deny other writers; a second instance must not truncate the first's record.
  record_file = CreateFileW(pending.c_str(), GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ,
                            nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (record_file == INVALID_HANDLE_VALUE) return;
  LARGE_INTEGER size = {};
  if (GetFileSizeEx(record_file, &size) && size.QuadPart > 0 && size.QuadPart <= 32768) {
    char old[32768] = {};
    DWORD count = 0;
    if (ReadFile(record_file, old, static_cast<DWORD>(size.QuadPart), &count, nullptr) &&
        count == static_cast<DWORD>(size.QuadPart) && count >= 15 && memcmp(old, "modu-native-v1\n", 15) == 0) {
      HANDLE saved = CreateFileW(previous_path, GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                                 CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (saved != INVALID_HANDLE_VALUE) {
        DWORD written = 0;
        WriteFile(saved, old, count, &written, nullptr);
        FlushFileBuffers(saved);
        CloseHandle(saved);
      }
    }
  }
  SetFilePointer(record_file, 0, nullptr, FILE_BEGIN);
  SetEndOfFile(record_file);
  AttachNativeCrashFilter();
}

void AttachNativeCrashFilter() {
  if (record_file == INVALID_HANDLE_VALUE) return;
  const auto displaced = SetUnhandledExceptionFilter(OnUnhandledException);
  if (displaced != OnUnhandledException) previous_filter = displaced;
}

bool NativeCrashRecorderActive() { return record_file != INVALID_HANDLE_VALUE; }

std::string ReadPreviousNativeCrash() {
  if (!previous_path[0]) return {};
  HANDLE saved = CreateFileW(previous_path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                             nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (saved == INVALID_HANDLE_VALUE) return {};
  LARGE_INTEGER size = {};
  std::string data;
  if (GetFileSizeEx(saved, &size) && size.QuadPart > 0 && size.QuadPart <= 32768) {
    data.resize(static_cast<size_t>(size.QuadPart));
    DWORD count = 0;
    if (!ReadFile(saved, &data[0], static_cast<DWORD>(data.size()), &count, nullptr) ||
        count != data.size()) data.clear();
  }
  CloseHandle(saved);
  return data;
}
