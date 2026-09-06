#ifndef MODU_NATIVE_CRASH_RECORDER_H_
#define MODU_NATIVE_CRASH_RECORDER_H_

#include <string>

// Installs before Flutter starts; no settings, user content or minidumps read.
void InitializeNativeCrashRecorder();
// Called once after engine/plugin initialization, which may install a filter.
void AttachNativeCrashFilter();
bool NativeCrashRecorderActive();
std::string ReadPreviousNativeCrash();

#endif
