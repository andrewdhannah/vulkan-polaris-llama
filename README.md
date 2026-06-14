# llama.cpp — Windows Local Lane (Radeon RX 570)

![llama](https://raw.githubusercontent.com/ggml-org/llama.brand/refs/heads/master/cover/llama-cpp/cover-llama-cpp-dark.svg)

**Machine:** AMD Radeon RX 570 4GB (Polaris) | Intel i5-3570K | Windows 10  
**Vulkan SDK:** 1.3.296.0 | **Driver:** AMD Adrenalin 26.5.2  
**Build:** MSVC Release, Polaris Vulkan QF 0 fix applied

---

## Topology

```
Mac Librarian / OpenWork
        ↓
  http://windows-pc:8080
        ↓
  Rust Router (llama-router.exe)  ← session management, context packing
        ↓
  http://127.0.0.1:9120
        ↓
  llama-server-mini.exe           ← single GPU worker, full offload
        ↓
  RX 570 model (phi-4)
```

**Security boundary:**
- `llama-server-mini.exe` binds to `127.0.0.1` only (localhost)
- Router binds to `0.0.0.0:8080` (LAN-facing)
- Router is the only network-exposed service

---

## Quick Start

### Option A: Direct (single session)

```powershell
.\model_manager.ps1 diagnose        # Pre-flight check
.\model_manager.ps1 start phi-4      # Launch chat server (port 9120)
.\model_manager.ps1 status           # Verify identity
.\model_manager.ps1 stop             # Graceful shutdown
```

Model loads in ~6s (warm cache) or ~90s (cold start).

### Option B: Router (multiple sessions)

```powershell
.\model_manager.ps1 start phi-4              # Start llama.cpp on port 9120
.\router\target\release\llama-router.exe     # Start router on port 8080
```

Then use port 8080 with `X-Librarian-Session` header for session management.

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

## Endpoints

### llama-server-mini (port 9120, localhost only)

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health` | Health check with model identity |
| `GET` | `/v1/models` | List available models |
| `POST` | `/v1/chat/completions` | Chat completion |
| `POST` | `/reset` | Clear conversation history + KV cache |

### Rust Router (port 8080, LAN-facing)

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health` | Router + llama.cpp health |
| `POST` | `/v1/chat/completions` | Session-routed chat completion |
| `GET` | `/sessions` | List active sessions |
| `GET` | `/sessions/{id}` | Get session transcript |
| `POST` | `/sessions/{id}/reset` | Clear session memory |

---

## Directory Layout

```
G:\llama.cpp\
├── models\                           ← GGUF model files
├── build_vs\bin\Release\             ← Compiled binaries
│   ├── llama-server-mini.exe         ← Hardened HTTP server (--alias + /reset)
│   └── llama-server.exe              ← Full server (VRAM-heavy, partial GPU)
├── examples/server-mini/
│   ├── server-mini.cpp               ← Patched with --alias + /reset
│   └── CMakeLists.txt
├── router/                           ← Rust session router
│   ├── src/main.rs
│   ├── Cargo.toml
│   └── target/release/llama-router.exe  ← 4.8 MB binary
├── model_manager.ps1                 ← Lifecycle, identity, diagnostics
├── docs/
│   ├── WINDOWS-RUST-ROUTER.md        ← Router documentation
│   ├── WINDOWS-LLAMA-MANAGER-HARDENING.md
│   ├── LLAMA-SERVER-MINI-ALIAS-PATCH.md
│   ├── TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md
│   ├── HANDOFF-WINDOWS-LLAMA-POC.md
│   └── LIBRARIAN-RUNTIME-CONTRACT.md
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

### Context Full?

```powershell
# Quick reset without restarting
Invoke-RestMethod -Uri "http://localhost:9120/reset" -Method Post

# Or use the router for automatic session management
.\router\target\release\llama-router.exe
```

---

## Build Notes

- **Vulkan Polaris fix** is already applied in `ggml/src/ggml-vulkan/ggml-vulkan.cpp`. Startup confirms with `=== Using C API device (QF 0) ===`.
- **Server-mini** uses `llama-server-mini.exe` compiled from `examples/server-mini/server-mini.cpp`. Patched with `--alias` and `/reset` endpoint.
- **Full server** (`llama-server.exe`) was built but is VRAM-heavy (~3.4 GB+) and only achieves partial GPU offload on the RX 570. Not recommended for this hardware.
- **Rust router** (`llama-router.exe`) is the preferred approach for multiple sessions. 4.8 MB binary, ~10 MB RAM, routes unlimited sessions through one llama.cpp worker.
- **Do not backport upstream full server** unless the API/build mismatch is explicitly resolved. The mini server + router approach is the correct architecture for 4GB VRAM.

---

## Documentation

| File | Purpose |
|------|---------|
| [`docs/WINDOWS-RUST-ROUTER.md`](docs/WINDOWS-RUST-ROUTER.md) | Router architecture, API, build instructions |
| [`docs/LLAMA-SERVER-MINI-ALIAS-PATCH.md`](docs/LLAMA-SERVER-MINI-ALIAS-PATCH.md) | `--alias` + `/reset` patch details |
| [`docs/WINDOWS-LLAMA-MANAGER-HARDENING.md`](docs/WINDOWS-LLAMA-MANAGER-HARDENING.md) | Manager script improvements |
| [`docs/TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md`](docs/TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md) | Survival guide for every failure mode |
| [`docs/HANDOFF-WINDOWS-LLAMA-POC.md`](docs/HANDOFF-WINDOWS-LLAMA-POC.md) | Clean handoff for future sessions |
| [`docs/LIBRARIAN-RUNTIME-CONTRACT.md`](docs/LIBRARIAN-RUNTIME-CONTRACT.md) | Substrate-agnostic runtime contract |
| [`LIBRARIAN_KNOWLEDGE.md`](LIBRARIAN_KNOWLEDGE.md) | Full operational context for next instance |
