# Handoff: Windows llama.cpp POC

> **Purpose:** Let a future session start clean with full context of all work.
> **Date:** 2026-06-13 (updated from 2026-06-12)
> **Last commit:** `d65ad67` (before router work)

---

## Current Known-Good State

| Item | Value |
|------|-------|
| **Git HEAD** | `d65ad67` — `Add Librarian Runtime Contract` |
| **Binary** | `build_vs\bin\Release\llama-server-mini.exe` (49.1 MB, rebuilt with `/reset`) |
| **Router** | `router\target\release\llama-router.exe` (4.8 MB) |
| **Full server** | `build_vs\bin\Release\llama-server.exe` (~200 MB, VRAM-heavy) |
| **Manager script** | `model_manager.ps1` |
| **Knowledge base** | `LIBRARIAN_KNOWLEDGE.md` |
| **Server source** | `examples/server-mini/server-mini.cpp` (patched with `--alias` + `/reset`) |
| **Vulkan backend** | `ggml/src/ggml-vulkan/ggml-vulkan.cpp` (Polaris QF 0 fix) |
| **Router source** | `router/src/main.rs` + `router/Cargo.toml` |

### Verified endpoints

```
GET  /health                    → {"status":"ok","model":"phi-4"}
GET  /v1/models                 → {"data":[{"id":"phi-4"}]}
POST /v1/chat/completions       → OpenAI-compatible response
POST /reset                     → {"status":"ok","message":"context reset"}
```

### Router endpoints (port 8080)

```
GET  /health                    → Router + llama.cpp health
POST /v1/chat/completions       → Session-routed chat completion
GET  /sessions                  → List active sessions
GET  /sessions/{id}             → Session transcript
POST /sessions/{id}/reset       → Clear session memory
```

### Known-good manager commands

```powershell
cd G:\llama.cpp

.\model_manager.ps1 diagnose       # Full system snapshot
.\model_manager.ps1 start phi-4     # Launch chat (port 9120)
.\model_manager.ps1 status          # Verify identity
.\model_manager.ps1 stop            # Graceful stop
```

---

## What Not To Do

### Do not assume `/health.model` is auto-detected from GGUF metadata

The `/health` endpoint's `model` field is **not** read from the GGUF file. It is whatever was passed via `--alias` at launch, or the C++ fallback (file stem). The manager must explicitly pass `--alias`.

### Do not trust old `llama-server-mini.exe` binaries

Any binary built before 2026-06-12 has hardcoded `qwen2.5-coder-1.5b-q8_0` in three endpoints. Always rebuild from source after pulling changes.

### Do not backport full upstream `examples/server/` blindly

The full server was built successfully but is **VRAM-heavy** (~3.4 GB+) and only achieves partial GPU offload on the RX 570 4GB. The mini server + router approach is preferred for this hardware.

### Do not erase dirty repo state with `git reset` or `git clean`

The pre-existing dirty state was intentional and committed. If the tree is dirty, investigate before resetting.

### Do not treat exact-prompt obedience failure as a runtime issue

A model that starts and generates tokens but fails to follow instructions is a **model capability limitation**, not a runtime failure. The three axes are independent:

1. Runtime pass (launch, endpoints, identity, lifecycle)
2. Instruction-following pass (prompt obedience, format compliance)
3. Manager lifecycle pass (ports, PIDs, errors, state transitions)

---

## What Was Hard-Learned

### 1. Stale model identity came from hardcoded server strings, not cache

We initially blamed Vulkan shader cache, file system caching, or stale HTTP responses. The real cause was three `"qwen2.5-coder-1.5b-q8_0"` string literals in `server-mini.cpp`. Always search for hardcoded identity strings when `/health` reports unexpected model names.

### 2. Mini server was the right patch target

The upstream `examples/server/` wasn't available at this commit. Rather than backporting a huge directory, the correct fix was a focused ~20-line patch to the existing mini server. This minimized risk, kept the build simple, and solved the specific problem.

### 3. Manager-owned identity is still required even when server health is fixed

Even with `--alias` working, the manager script is the source of truth. The server merely confirms. The `Classify-Identity -ExpectedAlias` pattern makes this explicit: the manager says "I expect `phi-4`", and the classifier says "does health match? yes → VERIFIED".

### 4. Polaris Vulkan path must remain protected

The `ggml-vulkan.cpp` patch for Polaris single-queue (QF 0) is critical. If this file is reverted or overwritten by an upstream merge, the server will crash at startup on `load_tensors` with multi-queue initialization. Always verify the startup log contains:

```
ggml_vulkan: using single QF 0 queue for Polaris compatibility
=== Using C API device (QF 0) ===
```

### 5. `.gitignore` must not hide source files

A broad `/examples/server-mini/` rule hides the source `.cpp` file from git. Always check with `git check-ignore -v <file>` before assuming a file is tracked. Use specific artifact patterns instead of directory-level ignores.

### 6. Two model instances don't fit in 4GB VRAM

Running two `llama-server-mini.exe` processes requires ~6.6 GB VRAM (2 × 3.3 GB). The RX 570 has 4 GB. The correct solution is a **router** that maintains session state outside VRAM and feeds one bounded context to one llama.cpp worker.

### 7. Full llama.cpp server is too heavy for RX 570

The full server (`llama-server.exe`) uses more VRAM than the mini server due to unified KV cache, parallel slots, and additional buffers. On the RX 570 4GB, it can only achieve partial GPU offload (some layers on CPU), making it slower than the mini server.

---

## Files in This Commit

```
examples/server-mini/server-mini.cpp  ← --alias + /reset endpoint
router/                               ← Rust router (src/main.rs, Cargo.toml)
docs/WINDOWS-RUST-ROUTER.md           ← Router documentation
docs/HANDOFF-WINDOWS-LLAMA-POC.md     ← This file (updated)
docs/TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md  ← Updated with router info
docs/LLAMA-SERVER-MINI-ALIAS-PATCH.md ← Updated with /reset endpoint
README.md                             ← Rewritten with full topology
LIBRARIAN_KNOWLEDGE.md                ← Updated with router context
```

---

## Remaining Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Embedding role non-functional | Cannot serve `/v1/embeddings` | Build full `llama-server.exe` or backport embedding handler |
| No TLS/HTTPS | All API traffic plaintext | Use SSH tunnel or VPN |
| No `--api-key` | Anyone on LAN can use the server | Firewall rule on port 8080/9120 |
| Console window visible | Minor UX annoyance | Start via scheduled task or system service |
| Cold start ~90s | First load after driver update is slow | Warm cache reduces to ~6s |
| Router is in-memory only | Session state lost on restart | Add SQLite persistence (planned) |
| No context summarization | Old turns dropped, not summarized | Add rolling summary (planned) |

---

## Next Recommended Steps

1. **Add SQLite persistence to router** — Survive restarts without losing session state
2. **Add context summarization** — Replace dropped turns with rolling summaries instead of truncation
3. **Add request size limits** — Prevent oversized prompts from overwhelming the server
4. **Add CORS configuration** — Allow browser-based clients
5. **Build Windows service wrapper** — Run router as a background service

---

*See also: [`WINDOWS-RUST-ROUTER.md`](WINDOWS-RUST-ROUTER.md), [`WINDOWS-LLAMA-MANAGER-HARDENING.md`](WINDOWS-LLAMA-MANAGER-HARDENING.md), [`LLAMA-SERVER-MINI-ALIAS-PATCH.md`](LLAMA-SERVER-MINI-ALIAS-PATCH.md), [`TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md`](TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md), [`LIBRARIAN-RUNTIME-CONTRACT.md`](LIBRARIAN-RUNTIME-CONTRACT.md)*
