# Librarian Runtime Contract

> **Purpose:** Define the minimum API surface and behavioral contract any local runtime must satisfy for The Librarian to route work safely.
> **Derived from:** Windows llama.cpp POC (RX 570, `server-mini`, `phi-4`) — committed at `37a7903`
> **Design principle:** Substrate-agnostic — same contract applies to llama.cpp, Ollama, vLLM, or any future runtime.

---

## Contract Summary

A local runtime is acceptable for The Librarian if it can:

1. **Declare identity** — name the model it is serving
2. **Pass health checks** — confirm readiness and identity on demand
3. **Serve bounded completions** — generate text within constraints
4. **Fail cleanly** — exit recognizably, not silently
5. **Expose lifecycle metadata** — enough for the manager to own lifecycle

---

## 1. Identity Declaration

### Required

The runtime must expose the model identity on at least one endpoint that The Librarian can query without generating tokens. The identity must be **deterministic** for a given loaded model — it is set at launch time and does not change until restart.

### Current implementation (llama.cpp)

| Endpoint | Response |
|----------|----------|
| `GET /health` | `{"model":"phi-4"}` |
| `GET /v1/models` | `{"data":[{"id":"phi-4"}]}` |

### Rule

```
manager alias == launch --alias == /health model == /v1/models id == completions model
```

The manager owns the intended identity. The runtime confirms it. Diagnose flags disagreement.

### Violation detection

If `Classify-Identity` returns `HEALTH_IDENTITY_DRIFT`, `PROCESS_DRIFT`, or `UNTRUSTED_RUNTIME`, The Librarian must **not route work** to that runtime until the identity is resolved.

---

## 2. Health Check

### Required

The runtime must expose a zero-token endpoint that returns:

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `status` | string | yes | Must be `"ok"` when ready |
| `model` | string | yes | The declared model identity |
| *(extensible)* | — | no | Additional metadata (context length, version, etc.) |

### Current implementation

```json
GET /health → {"status":"ok","model":"phi-4"}
```

### Timeout

The health check must respond within 5 seconds. If it does not, the runtime should be considered unreachable and The Librarian should attempt restart or fail to the next lane.

---

## 3. Bounded Completions

### Required

The runtime must accept a completion request with at minimum:

| Parameter | Required | Notes |
|-----------|----------|-------|
| `messages` | yes | Array of `{role, content}` objects |
| `max_tokens` | no | Upper bound on generation; runtime may have its own limit |

And return:

| Field | Required | Notes |
|-------|----------|-------|
| `model` | yes | Must match `/health` model |
| `choices[0].message.content` | yes | Generated text |
| `choices[0].finish_reason` | yes | `"stop"`, `"length"`, or error indicator |

### Current implementation

```json
POST /v1/chat/completions
{"messages":[{"role":"user","content":"Say hello"}],"max_tokens":10}
→ {"model":"phi-4","choices":[{"message":{"content":"Hello"},"finish_reason":"stop"}]}
```

### Bounds

The Librarian must be able to specify `max_tokens` up to at least 1024. The runtime must respect this bound or cap gracefully (return `finish_reason: "length"`). The runtime must not silently ignore the bound.

---

## 4. Clean Failure

### Required

The runtime must fail in one of these recognizable ways:

| Failure mode | Detection | Librarian action |
|-------------|-----------|-----------------|
| Process crash | Port closed, health timeout | Restart via manager |
| Model load failure | Process exits before port opens | Check logs, switch model |
| OOM (out of VRAM) | Process crash at `load_tensors` | Free memory, reduce context, switch model |
| Hang (infinite generation) | Health timeout during generation | Kill and restart |
| Invalid response (empty, malformed) | Parse failure in response | Retry, then fail to next lane |

### Current implementation

The `model_manager.ps1` state machine handles all five:

```
STARTING → LISTENING → HEALTH_RESPONDED → FAILED_TO_START
```

Each state has a timeout (180s total). The process is observed both via port liveness and health endpoint. If either fails, the manager reports `FAILED_TO_START` with the exit code and log path.

### Rule

A runtime that fails silently (produces no error, no exit code, no log) is unacceptable. Every failure path must produce at least one of: non-zero exit code, stderr message, or port remaining closed.

---

## 5. Lifecycle Metadata

### Required

The manager must be able to discover:

| Metadata | How | Notes |
|----------|-----|-------|
| PID | Process table | Which process owns the port |
| Command line | `Win32_Process.CommandLine` or `/proc/pid/cmdline` | What arguments were passed |
| Model path | `-m` argument | Which GGUF file is loaded |
| Port | Listening address | Where the runtime is reachable |
| Alias | `--alias` argument | What identity was declared |

### Current implementation

```powershell
Get-ProcessCmdLine -ProcessId <pid>
# Returns: "llama-server-mini.exe" -m "model.gguf" -p 9120 --alias "phi-4"
```

### PID file convention

The manager writes `<temp>/llama_manager_<port>.pid` containing the PID. On start, it checks for stale PID files. On stop, it removes the PID file.

---

## Contract Verification Procedure

The Librarian or any future instance should verify contract compliance by running:

```powershell
# 1. Start the runtime
.\model_manager.ps1 start <model>
# Expected: [HEALTH_RESPONDED] ... (reported: <alias>)
# Expected: [IDENTITY_MATCHED] VERIFIED

# 2. Query identity endpoints
Invoke-RestMethod http://localhost:<port>/health
# Expected: status="ok", model="<alias>"

Invoke-RestMethod http://localhost:<port>/v1/models
# Expected: data[0].id = "<alias>"

# 3. Test bounded completion
$body = @{messages=@(@{role="user";content="Reply exactly: pass"})} | ConvertTo-Json
Invoke-RestMethod http://localhost:<port>/v1/chat/completions -Method Post -Body $body -ContentType "application/json"
# Expected: model="<alias>", choices[0].finish_reason="stop"

# 4. Verify lifecycle
.\model_manager.ps1 status
# Expected: Identity: VERIFIED

.\model_manager.ps1 stop
# Expected: stopped, PID file removed

.\model_manager.ps1 diagnose
# Expected: port CLOSED, no orphan
```

All four steps must pass for the runtime to be considered contract-compliant.

---

## Implementation Status

| Contract clause | Status | Verified |
|----------------|--------|----------|
| Identity declaration | Implemented (server-mini.cpp `--alias`, 3 endpoints) | ✅ 2026-06-12 |
| Health check | Implemented (`/health` returns model + status) | ✅ 2026-06-12 |
| Bounded completions | Implemented (`/v1/chat/completions`, `max_tokens` respected) | ✅ 2026-06-12 |
| Clean failure | Implemented (state machine, port + health timeout) | ✅ 2026-06-12 |
| Lifecycle metadata | Implemented (PID file, cmdline parsing, `Get-ProcessCmdLine`) | ✅ 2026-06-12 |

---

## Substrate Portability Notes

This contract does **not** require:

- A specific GPU (Polaris, RDNA, CUDA, CPU-only)
- A specific server binary (mini server, full server, Ollama, vLLM)
- A specific model format (GGUF, safetensors, ONNX)
- A specific OS (Windows, Linux, macOS)
- A specific port (9120, 8080, 11434)

It requires:

- A stable identity declaration
- A responsive health endpoint
- Bounded, parseable completions
- Recognizable failure modes
- Exposed lifecycle metadata

Any runtime that satisfies these five clauses can serve as a Librarian local lane. The implementation details (Vulkan vs CUDA, mini vs full server, etc.) are irrelevant to the contract.

---

*Derived from: Windows llama.cpp POC at commit `37a7903`*
*Runtime hardening: `model_manager.ps1`, `server-mini.cpp`, `ggml-vulkan.cpp` (Polaris QF 0)*
*See also: [`HANDOFF-WINDOWS-LLAMA-POC.md`](HANDOFF-WINDOWS-LLAMA-POC.md)*
