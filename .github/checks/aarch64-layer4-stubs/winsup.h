#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <assert.h>
#include <stdint.h>
#include <string.h>

#define Peb ProcessEnvironmentBlock
#define FastPebLock Reserved4[2]
