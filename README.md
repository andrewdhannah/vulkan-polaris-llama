# llama.cpp — Windows Local Lane (Radeon RX 570)

![llama](https://raw.githubusercontent.com/ggml-org/llama.brand/refs/heads/master/cover/llama-cpp/cover-llama-cpp-dark.svg)

**Machine:** AMD Radeon RX 570 4GB (Polaris) | Intel i5-3570K | Windows 10  
**Vulkan SDK:** 1.3.296.0 | **Driver:** AMD Adrenalin 26.5.2  
**Build:** MSVC Release, Polaris Vulkan QF 0 fix applied

---

## Quick Start

```powershell
.\model_manager.ps1 diagnose        # Pre-flight check
.\model_manager.ps1 start phi-4      # Launch chat server
.\model_manager.ps1 status           # Verify identity
.\model_manager.ps1 stop             # Graceful shutdown
```

Model loads in ~6s (warm cache) or ~90s (cold start). Ports: **9120** (chat), **9121** (free), **9122** (embedding).

---

## Identity Architecture

```
Manager owns intended identity.
Server confirms active identity.
Diagnose flags disagreement.
```

The `model_manager.ps1` passes `--alias <name>` on launch. The server reports this alias in `/health`, `/v1/models`, and `/v1/chat/completions`. The `diagnose` command cross-checks all three sources plus the manager's intent.

| Source | What it provides |
|--------|-----------------|
| Manager config (`$Models`) | Expected alias (e.g. `phi-4`) |
| Process launch args | `--alias phi-4` |
| Server `/health` | `{"model":"phi-4"}` |
| Server `/v1/models` | `{"id":"phi-4"}` |
| Server chat completions | `"model":"phi-4"` |

All five must agree. If they don't, `Classify-Identity` reports one of: `VERIFIED`, `HEALTH_IDENTITY_DRIFT`, `PROCESS_DRIFT`, `REGISTRY_STALE`, `UNTRUSTED_RUNTIME`.

**Do not trust stale hardcoded model names from old binaries.** Before this hardening, `llama-server-mini.exe` returned hardcoded `qwen2.5-coder-1.5b-q8_0` on every endpoint regardless of loaded model. The fix was a backported `--alias` flag in `server-mini.cpp`.

---

## Models (RX 570 4GB)

| Name | Display | File | Size | VRAM | Speed |
|------|---------|------|------|------|-------|
| `phi-4` | Phi-4-mini 3.8B Q4_K_M | `microsoft_Phi-4-mini-instruct-Q4_K_M.gguf` | 2.32 GB | ~2.4 GB | 14-51 tok/s |
| `llama-3.2` | Llama 3.2 3B Q5_K_M | `Llama-3.2-3B-Instruct-Q5_K_M.gguf` | 2.16 GB | ~2.2 GB | 32-49 tok/s |
| `gemma-3` | Gemma 3 4B Q4_K_M | `gemma-3-4b-it-Q4_K_M.gguf` | 2.32 GB | ~2.4 GB | 19-35 tok/s |
| `qwen3` | Qwen3 4B Q4_K_M | `Qwen_Qwen3-4B-Q4_K_M.gguf` | 2.33 GB | ~2.4 GB | 22-40 tok/s |

---

## Directory Layout

```
G:\llama.cpp\
├── models\                           ← GGUF model files
├── build_vs\bin\Release\             ← Compiled binaries
│   └── llama-server-mini.exe         ← Hardened HTTP server (--alias support)
├── examples/server-mini/
│   ├── server-mini.cpp               ← Patched with --alias flag
│   └── CMakeLists.txt
├── model_manager.ps1                 ← Lifecycle, identity, diagnostics
├── docs/
│   ├── WINDOWS-LLAMA-MANAGER-HARDENING.md
│   ├── LLAMA-SERVER-MINI-ALIAS-PATCH.md
│   ├── TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md
│   └── HANDOFF-WINDOWS-LLAMA-POC.md
├── LIBRARIAN_KNOWLEDGE.md            ← Full context for future instances
├── ggml/src/ggml-vulkan/ggml-vulkan.cpp  ← Polaris QF 0 fix applied
├── vulkan_polaris_fix.patch          ← The Polaris GPU fix patch
└── (llama.cpp source code...)
```

---

## Troubleshooting

First command for any issue:

```powershell
.\model_manager.ps1 diagnose
```

This checks: binary existence, model files, port availability, GPU detection, running processes, identity verification, PID file consistency, and disk space.

Detailed troubleshooting guide: [`docs/TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md`](docs/TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md)

---

## Build Notes

- **Vulkan Polaris fix** is already applied in `ggml/src/ggml-vulkan/ggml-vulkan.cpp`. Startup confirms with `=== Using C API device (QF 0) ===`.
- **Server-mini** uses `llama-server-mini.exe` compiled from `examples/server-mini/server-mini.cpp`. This is **not** the full upstream `examples/server/` — it has no `--embedding`, no `--api-key`, no `--host`, no TLS.
- **Do not backport upstream full server** unless the API/build mismatch with `llama.h` at commit `7c158fb` is explicitly resolved.
- Full build guide: [`docs/WINDOWS-LLAMA-MANAGER-HARDENING.md`](docs/WINDOWS-LLAMA-MANAGER-HARDENING.md)
- Alias patch details: [`docs/LLAMA-SERVER-MINI-ALIAS-PATCH.md`](docs/LLAMA-SERVER-MINI-ALIAS-PATCH.md)
- Lessons learned & handoff: [`docs/HANDOFF-WINDOWS-LLAMA-POC.md`](docs/HANDOFF-WINDOWS-LLAMA-POC.md)
