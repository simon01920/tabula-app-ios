// SwiftPM cannot select sources per architecture, so the per-arch ggml-cpu kernels are pulled in here by
// the preprocessor (upstream CMake picks exactly one of these files). Other arches use the generic
// fallbacks wired up by ggml-cpu/arch-fallback.h.
#if defined(__x86_64__) || defined(_M_X64)
#include "../upstream/ggml/src/ggml-cpu/arch/x86/quants.c"
#elif defined(__aarch64__) || defined(_M_ARM64)
#include "../upstream/ggml/src/ggml-cpu/arch/arm/quants.c"
#else
typedef int tabula_cpu_arch_quants_empty;
#endif
