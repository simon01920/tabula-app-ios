// Metal backend (Apple only). TABULA_LLAMA_METAL is defined by Package.swift for iOS/macOS targets only,
// so this is an empty translation unit on Linux. UNVERIFIED on iOS until an iOS SDK is available.
#if defined(__APPLE__) && defined(TABULA_LLAMA_METAL)
#include "../upstream/ggml/src/ggml-metal/ggml-metal-ops.cpp"
#endif
