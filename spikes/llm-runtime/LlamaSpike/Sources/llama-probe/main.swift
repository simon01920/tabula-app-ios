// llama-probe — Phase 0 spike. Proves that the llama.cpp C API is reachable from Swift 6 (strict
// concurrency) when llama.cpp is compiled from source by SwiftPM, and that GBNF grammar-constrained
// sampling works through the C API. Uses NO model weights:
//   llama-probe                      -> backend init, system info, backend device list
//   llama-probe <vocab-only.gguf>    -> additionally loads a vocab-only GGUF (tokenizer data shipped in the
//                                       llama.cpp repo) and runs a model-free "random walk" under a timetable-
//                                       cell grammar, then validates the produced text with JSONSerialization.
import CLlama
import Foundation

func cstr(_ p: UnsafePointer<CChar>?) -> String { p.map { String(cString: $0) } ?? "<nil>" }

/// Deterministic RNG so the run is reproducible.
struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func pieceBytes(_ vocab: OpaquePointer?, _ token: llama_token) -> [UInt8] {
    var buf = [CChar](repeating: 0, count: 64)
    var n = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
    if n < 0 {
        buf = [CChar](repeating: 0, count: Int(-n))
        n = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
    }
    return buf.prefix(Int(max(n, 0))).map { UInt8(bitPattern: $0) }
}

let clock = ContinuousClock()

// 1. Backend init + system info -------------------------------------------------------------------------
let tInit = clock.now
llama_backend_init()
print("llama_backend_init: ok (\(clock.now - tInit))")
print("llama_print_system_info: \(cstr(llama_print_system_info()))")
print("llama_max_devices=\(llama_max_devices()) supports_mmap=\(llama_supports_mmap()) supports_gpu_offload=\(llama_supports_gpu_offload())")
let devCount = ggml_backend_dev_count()
print("ggml backend devices: \(devCount)")
for i in 0..<devCount {
    let dev = ggml_backend_dev_get(i)
    print("  [\(i)] \(cstr(ggml_backend_dev_name(dev))) | \(cstr(ggml_backend_dev_description(dev))) | type=\(ggml_backend_dev_type(dev).rawValue)")
}

// 2. Optional: GBNF grammar-constrained sampling without a model -----------------------------------------
var exitCode: Int32 = 0
if CommandLine.arguments.count >= 2 {
    let vocabPath = CommandLine.arguments[1]
    var mparams = llama_model_default_params()
    mparams.vocab_only = true
    let tLoad = clock.now
    if let model = llama_model_load_from_file(vocabPath, mparams) {
        let vocab = llama_model_get_vocab(model)
        let nVocab = Int(llama_vocab_n_tokens(vocab))
        print("vocab-only load: \(vocabPath) n_tokens=\(nVocab) (\(clock.now - tLoad))")

        // A cell of a timetable, roughly the shape the Phase 9 normaliser will emit.
        let grammar = #"""
        root    ::= "{\"day\":" day ",\"period\":" period ",\"subject\":" text ",\"room\":" (text | "null") "}"
        day     ::= "\"mon\"" | "\"tue\"" | "\"wed\"" | "\"thu\"" | "\"fri\"" | "\"sat\"" | "\"unknown\""
        period  ::= [1-9] | "1" [0-6]
        text    ::= "\"" char{1,20} "\""
        char    ::= [^"\\\x00-\x1f]
        """#

        // Negative check: a malformed grammar must be rejected (NULL), not crash.
        let bad = llama_sampler_init_grammar(vocab, "root ::= (", "root")
        print("malformed grammar rejected: \(bad == nil)")
        if let bad { llama_sampler_free(bad) }

        if let sampler = llama_sampler_init_grammar(vocab, grammar, "root") {
            var rng = SplitMix64(state: 42)
            var candidates = [llama_token_data](repeating: llama_token_data(id: 0, logit: 0, p: 0), count: nVocab)
            var out: [UInt8] = []
            var finished = false
            var steps = 0
            var allowedHistogram: [Int] = []
            let tWalk = clock.now
            while steps < 256 {
                for i in 0..<nVocab { candidates[i] = llama_token_data(id: llama_token(i), logit: 0, p: 0) }
                var allowed: [llama_token] = []
                candidates.withUnsafeMutableBufferPointer { buf in
                    var arr = llama_token_data_array(data: buf.baseAddress, size: buf.count, selected: -1, sorted: false)
                    llama_sampler_apply(sampler, &arr)
                    if let data = arr.data {
                        for j in 0..<arr.size where data[j].logit.isFinite { allowed.append(data[j].id) }
                    }
                }
                allowedHistogram.append(allowed.count)
                guard !allowed.isEmpty else { print("FAIL: grammar allows no token at step \(steps)"); break }
                let token = allowed[Int(rng.next() % UInt64(allowed.count))]
                if llama_vocab_is_eog(vocab, token) { finished = true; break }
                llama_sampler_accept(sampler, token)
                out += pieceBytes(vocab, token)
                steps += 1
            }
            let text = String(decoding: out, as: UTF8.self)
            print("constrained walk: steps=\(steps) finished_with_eog=\(finished) (\(clock.now - tWalk))")
            print("allowed tokens per step (first 12): \(allowedHistogram.prefix(12).map(String.init).joined(separator: " "))")
            print("output: \(text)")
            let valid = (try? JSONSerialization.jsonObject(with: Data(out))) != nil
            print("JSONSerialization accepts output: \(valid)")
            if !(valid && finished) { exitCode = 2 }
            llama_sampler_free(sampler)
        } else {
            print("FAIL: llama_sampler_init_grammar returned NULL for the timetable grammar")
            exitCode = 3
        }
        llama_model_free(model)
    } else {
        print("FAIL: could not load vocab-only GGUF at \(vocabPath)")
        exitCode = 4
    }
}

llama_backend_free()
print("llama_backend_free: ok")
exit(exitCode)
