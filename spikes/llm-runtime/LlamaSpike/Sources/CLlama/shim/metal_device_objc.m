// Metal backend Objective-C part (Apple only; manual retain/release -> Package.swift passes -fno-objc-arc).
// Empty translation unit on Linux. UNVERIFIED on iOS until an iOS SDK is available.
#if defined(__APPLE__) && defined(TABULA_LLAMA_METAL)
#include "../upstream/ggml/src/ggml-metal/ggml-metal-device.m"
#endif
