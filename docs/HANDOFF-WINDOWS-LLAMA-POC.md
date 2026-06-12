# Handoff: Windows llama.cpp POC

> **Purpose:** Let a future session start clean with full context of today's work.
> **Date:** 2026-06-12  
> **Last commit:** `f46bf9b`

---

## Current Known-Good State

| Item | Value |
|------|-------|
| **Git HEAD** | `f46bf9b` — `feat: backport --alias flag to llama-server-mini + identity system` |
| **Binary** | `G:\llama.cpp\build_vs\bin\Release\llama-server-mini.exe` (49.1 MB, built 2026-06-12) |
| **Manager script** | `G:\llama.cpp\model_manager.ps1` |
| **Knowledge base** | `G:\llama.cpp\LIBRARIAN_KNOWLEDGE.md` |
| **Server source** | `examples/server-mini/server-mini.cpp` (patched with `--alias`) |
| **Vulkan backend** | `ggml/src/ggml-vulkan/ggml-vulkan.cpp` (Polaris QF 0 fix applied) |

### Verified model alias test: `phi-4`

```json
GET /health        → {"status":"ok","model":"phi-4"}
GET /v1/models     → {"data":[{"id":"phi-4","object":"model","owned_by":"local"}]}
POST /chat/completions → "model":"phi-4" + "Hello! How can I assist you today?"
```

### Known-good manager commands

```powershell
cd G:\llama.cpp

.\model_manager.ps1 diagnose       # Full system snapshot
.\model_manager.ps1 start phi-4     # Launch chat (port 9120)
.\model_manager.ps1 status          # Verify identity
.\model_manager.ps1 stop            # Graceful stop
.\model_manager.ps1 embed-start     # Launch embedding (port 9122)
.\model_manager.ps1 embed-stop      # Stop embedding
```

---

## What Not To Do

### Do not assume `/health.model` is auto-detected from GGUF metadata

The `/health` endpoint's `model` field is **not** read from the GGUF file. It is whatever was passed via `--alias` at launch, or the C++ fallback (file stem). The manager must explicitly pass `--alias`.

### Do not trust old `llama-server-mini.exe` binaries

Any binary built before 2026-06-12 has hardcoded `qwen2.5-coder-1.5b-q8_0` in three endpoints. Always rebuild from source after pulling changes.

### Do not backport full upstream `examples/server/` blindly

The full server directory does not exist at commit `7c158fb`. Cherry-picking from a newer commit may break the `llama.h` API. Only attempt this if:

1. You can resolve the API version mismatch
2. You accept the ~2000+ line merge
3. You verify all existing identity features still work

### Do not erase dirty repo state with `git reset` or `git clean`

The pre-existing dirty state (CRLF in README, CMakeLists.txt changes, Polaris fix) was intentional and committed. If the tree is dirty, investigate before resetting.

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

---

## Files in This Commit

```
commit f46bf9b6cf7ed26794a209fea9c3f047ad976ca3
Author: Andrew Hannah <andrewdhannah@users.noreply.github.com>
Date:   Fri Jun 12 13:06:58 2026 -0400

 feat: backport --alias flag to llama-server-mini + identity system

 .gitignore                           |  63 +++
 LIBRARIAN_KNOWLEDGE.md               | 477 +++++++++++++++++
 README.md                            | 636 ++--------------------
 _validate.ps1                        |   8 +
 examples/CMakeLists.txt              |   1 +
 examples/server-mini/CMakeLists.txt  |   7 +
 examples/server-mini/server-mini.cpp | 770 +++++++++++++++++++++++++++
 ggml/src/ggml-vulkan/ggml-vulkan.cpp |  81 ++-
 model_manager.ps1                    | 995 +++++++++++++++++++++++++++++++++++
 9 files changed, 2430 insertions(+), 608 deletions(-)
```

---

## Remaining Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Embedding role non-functional | Cannot serve `/v1/embeddings` | Build full `llama-server.exe` or backport embedding handler |
| No TLS/HTTPS | All API traffic plaintext | Use SSH tunnel or VPN |
| No `--api-key` | Anyone on LAN can use the server | Firewall rule on port 9120 |
| Console window visible | Minor UX annoyance | Start via scheduled task or system service |
| Cold start ~90s | First load after driver update is slow | Warm cache reduces to ~6s |

---

## Next Recommended Step

**Build and validate embedding support.** This is the single biggest gap:

1. Either backport the `/v1/embeddings` handler to `server-mini.cpp` (~100 lines)
2. Or cherry-pick the full `examples/server/` from a newer upstream commit
3. Then verify `embed-start` → `POST /v1/embeddings` → valid vector response
4. Update identity verification for the embedding role

---

*See also: [`WINDOWS-LLAMA-MANAGER-HARDENING.md`](WINDOWS-LLAMA-MANAGER-HARDENING.md), [`LLAMA-SERVER-MINI-ALIAS-PATCH.md`](LLAMA-SERVER-MINI-ALIAS-PATCH.md), [`TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md`](TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md), [`LIBRARIAN-RUNTIME-CONTRACT.md`](LIBRARIAN-RUNTIME-CONTRACT.md)*
