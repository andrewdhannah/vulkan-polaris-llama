# Big Pickle — llama.cpp Workspace

![llama](https://raw.githubusercontent.com/ggml-org/llama.brand/refs/heads/master/cover/llama-cpp/cover-llama-cpp-dark.svg)

**Machine**: AMD Radeon RX 570 4GB | Intel i5-3570K | Windows 10  
**Vulkan SDK**: 1.3.296.0 | **Driver**: AMD Adrenalin 26.5.2  
**Build**: MSVC Release, Polaris Vulkan fix applied

---

## Quick Start

| Model | Script | Port |
|-------|--------|------|
| Qwen2.5 Coder 1.5B (Q8_0) | `start_qwen_coder.bat` | 8080 |
| Qwen2.5 MOE 2x1.5B (Q4_K_M) | `start_moe.bat` | 8080 |
| Gemma 3 4B (Q4_K_M) | `start_gemma3.bat` | 8080 |
| Gemma 4 4B (Q2_K_P) | `start_gemma4.bat` | 8080 |

Just double-click any `.bat` to start the server. Wait ~12s for the model to load, then:

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}],"stream":false}'
```

---

## Directory Layout

```
G:\llama.cpp\
├── models\                           ← All GGUF model files (4 models)
│   ├── qwen2.5-coder-1.5b-instruct-q8_0.gguf
│   ├── Qwen2.5-MOE-2X1.5B-...Q4_k_m.gguf
│   ├── gemma-3-4b-it-Q4_K_M.gguf
│   └── Gemma-4-E2B-Uncensored-...Q2_K_P.gguf
├── build_vs\bin\Release\             ← Compiled binaries
│   └── llama-server-mini.exe         ← HTTP inference server
├── build\                            ← Ninja build (incomplete, can delete)
├── start_qwen_coder.bat              ← Launcher scripts
├── start_moe.bat
├── start_gemma3.bat
├── start_gemma4.bat
├── benchmark_report.md               ← Model comparison results
├── README.md                         ← This file
├── vulkan_polaris_fix.patch          ← The Polaris GPU fix patch
└── (llama.cpp source code...)
```

**Related project**: `G:\vulkan-polaris-llama\` — the Vulcan project with patch, diagnostics, and docs.

---

## Models

| Model | File | Size | Quant |
|-------|------|------|-------|
| Qwen2.5 Coder 1.5B Instruct | `qwen2.5-coder-1.5b-instruct-q8_0.gguf` | 1.76 GB | Q8_0 |
| Qwen2.5 MOE 2x1.5B | `Qwen2.5-MOE-...Q4_k_m.gguf` | 2.34 GB | Q4_K_M |
| Gemma 3 4B IT | `gemma-3-4b-it-Q4_K_M.gguf` | 2.32 GB | Q4_K_M |
| Gemma 4 4B (Uncensored) | `Gemma-4-E2B-...Q2_K_P.gguf` | 2.80 GB | Q2_K_P |

---

## Notes

- The Polaris Vulkan patch is already applied in the source tree.  
- Use `build_vs` (MSVC), not `build` (ninja) — the ninja build is incomplete.  
- Server-mini maintains conversation state server-side — send consecutive prompts without resending history.  
- Maximum context: 16,384 tokens (set in .bat files).  
