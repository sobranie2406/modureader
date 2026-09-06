// Standalone test helper only. Never linked into the app. Run in an isolated
// Windows test account: it deliberately crashes ONLY its own child process.
#include <windows.h>
#include <cassert>
#include <string>
#include "../../windows/runner/native_crash_recorder.h"

int wmain(int argc, wchar_t**) {
  if (argc > 1) {
    SetErrorMode(SEM_NOGPFAULTERRORBOX);
    InitializeNativeCrashRecorder();
    RaiseException(EXCEPTION_ACCESS_VIOLATION, EXCEPTION_NONCONTINUABLE, 0, nullptr);
    return 1;
  }
  wchar_t path[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring command = L"\"" + std::wstring(path) + L"\" --crash-child";
  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION child = {};
  assert(CreateProcessW(nullptr, &command[0], nullptr, nullptr, FALSE, 0, nullptr, nullptr, &startup, &child));
  assert(WaitForSingleObject(child.hProcess, 15000) == WAIT_OBJECT_0);
  CloseHandle(child.hProcess);
  CloseHandle(child.hThread);
  InitializeNativeCrashRecorder();
  assert(NativeCrashRecorderActive());
  const auto record = ReadPreviousNativeCrash();
  assert(record.find("code=c0000005") != std::string::npos);
  assert(record.find("frame=") != std::string::npos);
  assert(record.find("\\Users\\") == std::string::npos);
  assert(record.size() <= 32768);
  return 0;
}
