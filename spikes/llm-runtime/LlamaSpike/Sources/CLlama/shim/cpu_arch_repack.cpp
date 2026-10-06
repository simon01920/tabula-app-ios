// See cpu_arch_quants.c.
#if defined(__x86_64__) || defined(_M_X64)
#include "../upstream/ggml/src/ggml-cpu/arch/x86/repack.cpp"
#elif defined(__aarch64__) || defined(_M_ARM64)
#include "../upstream/ggml/src/ggml-cpu/arch/arm/repack.cpp"
#endif
