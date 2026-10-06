// Upstream b11382 src/models/clef.cpp uses std::find without #include <algorithm>. The upstream CMake
// build compiles src/models/*.cpp as unity (jumbo) translation units, which masks the missing include;
// SwiftPM compiles each file separately, so clang + libstdc++ rejects it. Package.swift excludes the
// original file and compiles it through this wrapper instead. Remove when fixed upstream.
#include <algorithm>
#include "../upstream/src/models/clef.cpp"
