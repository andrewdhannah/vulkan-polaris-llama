# llama-server-mini `--alias` Patch

> **Date:** 2026-06-12  
> **File patched:** `examples/server-mini/server-mini.cpp`

---

## Problem

The `llama-server-mini.exe` binary returned a hardcoded model identity `qwen2.5-coder-1.5b-q8_0` on all three identity endpoints:

| Endpoint | Hardcoded Value |
|----------|----------------|
| `GET /health` | `{"model":"qwen2.5-coder-1.5b-q8_0"}` |
| `GET /v1/models` | `{"id":"qwen2.5-coder-1.5b-q8_0"}` |
| `POST /v1/chat/completions` | `"model":"qwen2.5-coder-1.5b-q8_0"` |

This caused **model identity drift**: the server would always report itself as `qwen2.5-coder-1.5b-q8_0` regardless of which GGUF model was actually loaded. The `/health` field is **not** auto-detected from GGUF metadata — it is a compile-time or launch-time setting.

Upstream context: [llama.cpp issue #11069](https://github.com/ggml-org/llama/issues/11069), [#10056](https://github.com/ggml-org/llama/issues/10056).

---

## Finding: Why Not Backport Upstream Server

The full upstream `examples/server/` directory (with full `--alias`, `--embedding`, `--api-key`, TLS support) **does not exist at this commit** (`7c158fb`). Only `examples/server-mini/` is present.

Backporting the full server is unsafe because:

1. The local `llama.h` / `llama.cpp` API may not match what the newer upstream `examples/server/` expects
2. It adds ~2000+ lines of C++ with auth middleware, streaming, embedding, and multi-model support we don't need
3. It would require merging CMakeLists.txt changes across multiple directories

**Correct approach:** Patch the existing `examples/server-mini/server-mini.cpp` with a focused ~20-line `--alias` backport.

---

## Patch Details

### Changes Made

| Change | Lines | Purpose |
|--------|-------|---------|
| `static std::string g_alias;` | +1 | Global alias variable (in config section) |
| `--alias` in `print_usage` | +1 | Document in help text |
| `strcmp(argv[i], "--alias")` parsing | +2 | CLI flag handler |
| Fallback computation | +6 | Path → filename stem (deterministic) |
| Startup log message | +1 | `[server] Starting (alias: %s)...` |
| `/v1/models` uses `g_alias` | ~2 | Dynamic response |
| `/health` uses `g_alias` | ~2 | Dynamic response |
| `/v1/chat/completions` uses `g_alias` | ~2 | Dynamic response |

### Fallback Logic (when `--alias` is not passed)

```cpp
// Derive alias from model filename (strip path and extension)
size_t last_slash = g_model_path.find_last_of("/\\");
std::string filename = (last_slash == std::string::npos) ? g_model_path : g_model_path.substr(last_slash + 1);
size_t dot = filename.find_last_of('.');
g_alias = (dot == std::string::npos) ? filename : filename.substr(0, dot);
```

This is **deterministic**: the same GGUF file always produces the same fallback alias.

**Examples:**

| Model Path | Fallback Alias |
|-----------|---------------|
| `models/microsoft_Phi-4-mini-instruct-Q4_K_M.gguf` | `microsoft_Phi-4-mini-instruct-Q4_K_M` |
| `models/Qwen_Qwen3-4B-Q4_K_M.gguf` | `Qwen_Qwen3-4B-Q4_K_M` |
| `models/snowflake-arctic-embed-m-long-Q4_0.gguf` | `snowflake-arctic-embed-m-long-Q4_0` |

### Architecture Rule

```
manager alias == launch --alias == /health model == /v1/models id == completions model
```

If any of these disagree, classify as identity drift:

| Pattern | Classification |
|---------|---------------|
| All match | `VERIFIED` |
| Manager's `--alias` matches health | `VERIFIED` (alias-aware) |
| Health differs from process/registry | `HEALTH_IDENTITY_DRIFT` |
| Process differs from health/registry | `PROCESS_DRIFT` |
| Registry differs from process/health | `REGISTRY_STALE` |
| None match | `UNTRUSTED_RUNTIME` |

---

## Verification

After patching and rebuilding, the server was tested with `--alias phi-4`:

```json
GET /health        → {"status":"ok","model":"phi-4"}
GET /v1/models     → {"data":[{"id":"phi-4","object":"model","owned_by":"local"}]}
POST /chat/...     → "model":"phi-4" + valid text
```

Without `--alias`, the fallback correctly uses the GGUF filename stem:

```json
GET /health → {"status":"ok","model":"microsoft_Phi-4-mini-instruct-Q4_K_M"}
```

---

## Rebuild Instructions

```powershell
# Kill any running server first (LNK1104 fix)
Get-Process -Name llama-server-mini -ErrorAction SilentlyContinue | Stop-Process -Force

# Rebuild
cd G:\llama.cpp\build_vs
cmake --build . --target llama-server-mini --config Release
```

Output: `G:\llama.cpp\build_vs\bin\Release\llama-server-mini.exe` (49.1 MB)

---

## Related

- [WINDOWS-LLAMA-MANAGER-HARDENING.md](WINDOWS-LLAMA-MANAGER-HARDENING.md) — Manager script improvements
- [TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md](TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md) — Survival guide
- [HANDOFF-WINDOWS-LLAMA-POC.md](HANDOFF-WINDOWS-LLAMA-POC.md) — Clean handoff for future sessions
