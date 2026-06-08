# LLM Benchmark Report — AMD RX 570 4GB (Polaris)

> **Date:** June 8, 2026
> **System:** Windows 10, i5-3570K (no AVX2/FMA), AMD Radeon RX 570 4GB
> **Backend:** llama.cpp custom build with Vulkan Polaris fix

---

## Test Setup

### Hardware
| Component | Detail |
|-----------|--------|
| GPU | AMD Radeon RX 570 4GB (Polaris gfx803) |
| Driver | AMD Adrenalin 26.5.2, Vulkan SDK 1.3.296.0 |
| CPU | Intel i5-3570K (Ivy Bridge, no AVX2/FMA) |
| RAM | 16 GB DDR3 |
| OS | Windows 10.0.19045 |

### Software
| Component | Detail |
|-----------|--------|
| Inference Engine | llama.cpp custom build (MSVC, Vulkan) |
| Server | `llama-server-mini` (OpenAI-compatible API) |
| Polaris Fix | Single QF 0 queue, C API, minimal pNext chain |
| Context Size | 4096 tokens |
| Max Predict | 1024 tokens |
| Temperature | 0.7 (single-turn) / 0.3–0.7 (multi-turn) |
| GPU Layers | All layers offloaded (`-ngl 99`) |

### Benchmarks Performed

1. **Simple QA** — "What is the capital of France and its population?" (up to 256 tokens)
2. **Complex Reasoning** — "Explain P vs NP. Why is it important? Example of NP-complete problem." (up to 1024 tokens)
3. **Code Generation** — "Write a complete Python merge sort with comments on time and space complexity." (up to 1024 tokens)
4. **Math** — Train A 60 mph / Train B 40 mph / 200 miles apart — how long to meet? (up to 512 tokens)
5. **Multi-turn Context** — 4-turn conversation testing recall of name (Andrew), city (Toronto), and job (software engineer)

---

## Results

### 1. Phi-4-mini 3.8B Q4_K_M ⭐ Best All-Rounder
| Test | Time | tok/s | Verdict |
|------|------|-------|---------|
| Simple QA | 5.1s | 14.2 | ✅ Correct (Paris, ~2.1M) |
| Complex Reasoning | 9.7s | 50.8 | ✅ Excellent, well-structured |
| Code Generation | 13.1s | 37.5 | ✅ Full merge sort, complete & correct |
| Math Problem | 4.4s | 29.3 | ✅ **2 hours — CORRECT** |
| Multi-turn T1 | 2.1s | — | ✅ Greeted Andrew, Toronto, SWE |
| Multi-turn T2 | 5.6s | — | ✅ Remembered Toronto |
| Multi-turn T3 | 12.6s | — | ✅ Remembered Toronto + job |
| Multi-turn T4 | 0.7s | — | ✅ Remembered name "Andrew" |

**File:** `microsoft_Phi-4-mini-instruct-Q4_K_M.gguf` (2.32 GB)
**Strengths:** Best conversational quality, great code, perfect math, solid context retention
**Weaknesses:** Slowest prompt processing speed (14 t/s on simple QA)

---

### 2. Llama 3.2 3B Q5_K_M 🚀 Fastest
| Test | Time | tok/s | Verdict |
|------|------|-------|---------|
| Simple QA | **2.3s** | **44.5** | ✅ Correct (Paris, ~2.1M) |
| Complex Reasoning | 18.8s | 48.6 | ✅ Good explanation |
| Code Generation | 18.5s | 39.0 | ✅ Complete merge sort |
| Math Problem | 9.0s | 32.3 | ✅ **2 hours — CORRECT** |
| Multi-turn T1 | 3.0s | — | ✅ Greeted Andrew |
| Multi-turn T2 | 11.2s | — | ✅ Remembered Toronto |
| Multi-turn T3 | 12.9s | — | ✅ Remembered Toronto + job |
| Multi-turn T4 | 0.4s | — | ✅ Remembered name "Andrew" |

**File:** `Llama-3.2-3B-Instruct-Q5_K_M.gguf` (2.16 GB)
**Strengths:** Fastest overall, good quality across all tests
**Weaknesses:** Slightly less thorough than Phi-4 on complex topics

---

### 3. Gemma 3 4B Q4_K_M 🥉 Solid Performer
| Test | Time | tok/s | Verdict |
|------|------|-------|---------|
| Simple QA | 4.3s | 19.1 | ✅ Correct (Paris, ~2.1M) |
| Complex Reasoning | 29.0s | 35.0 | ✅ Great, includes resource links |
| Code Generation | 32.8s | 29.0 | ✅ Full merge sort with thorough docs |
| Math Problem | 12.9s | 27.3 | ✅ **2 hours — CORRECT** |
| Multi-turn T1 | 2.0s | — | ✅ Greeted Andrew |
| Multi-turn T2 | 10.0s | — | ✅ Remembered Toronto (detailed) |
| Multi-turn T3 | 26.2s | — | ✅ Remembered Toronto + job (extensive) |
| Multi-turn T4 | 0.8s | — | ✅ Remembered name "Andrew" |

**File:** `gemma-3-4b-it-Q4_K_M.gguf` (2.32 GB)
**Strengths:** Verbose, thorough responses; excellent multi-turn depth
**Weaknesses:** Slowest generation speed, very wordy

---

### 4. Qwen3 4B Q4_K_M ⚠️ Good but Bloated
| Test | Time | tok/s | Verdict |
|------|------|-------|---------|
| Simple QA | 16.2s | 39.5 | ✅ Correct (Paris, ~2.1M) |
| Complex Reasoning | 31.8s | 37.3 | ✅ Good, but wrapped in `<think>` |
| Code Generation | 36.5s | 31.0 | ⚠️ Cut off at end |
| Math Problem | 27.1s | 22.3 | ✅ **2 hours — CORRECT** |
| Multi-turn T1 | 11.4s | — | ✅ Remembered Andrew, Toronto, SWE |
| Multi-turn T2 | 19.3s | — | ❌ **Context full** (blew 4096 ctx) |
| Multi-turn T3 | — | — | ❌ Context full |
| Multi-turn T4 | — | — | ❌ Context full |

**File:** `Qwen_Qwen3-4B-Q4_K_M.gguf` (2.33 GB)
**Strengths:** Good single-turn quality, math correct
**Weaknesses:** `<think>` tags double output size; 4096 context insufficient for multi-turn; verbose reasoning overhead

---

### 5. Failed / Non-Viable Models

| Model | File Size | Issue |
|-------|-----------|-------|
| **Gemma 4 4B Q2_K_P** | 2.80 GB | Chat template mismatch — `failed to apply chat template` |
| **Qwen2.5 Coder 1.5B Q8_0** | 1.76 GB | Too small; repetitive responses, can't hold context |
| **Qwen MOE 2x1.5B Q4_K_M** | 2.34 GB | Ruminative `<think>` loops; first QA timed out |
| **Llama3-8B-BitNet TQ1_0** | 2.06 GB | ⚡ Loads but Vulkan crashes on inference; CPU-only is 0.07 t/s on i5-3570K; poor output quality from GGUF conversion |

---

## Rankings

| Rank | Model | Speed | Quality | Multi-turn | Overall |
|------|-------|-------|---------|------------|---------|
| 🥇 | **Phi-4-mini 3.8B Q4_K_M** | B | A+ | A+ | **Best All-Rounder** |
| 🥈 | **Llama 3.2 3B Q5_K_M** | A+ | A- | A | **Fastest Daily Driver** |
| 🥉 | **Gemma 3 4B Q4_K_M** | C+ | A | A | **Best Verbose Assistant** |
| 4 | Qwen3 4B Q4_K_M | B | B- | D | Needs >8K context |

---

## Recommendations

### For general use (chat, coding, Q&A):
**Phi-4-mini 3.8B** — best quality, math, and context retention. Accept the slower prompt eval.

### For speed-sensitive tasks (tool calls, automation):
**Llama 3.2 3B** — fastest generation by far, still good quality.

### For thorough/verbose responses:
**Gemma 3 4B** — produces the most detailed answers, good for research.

### Not recommended:
- **Qwen3 4B** at 4096 context — `<think>` tag overhead kills multi-turn
- **Anything 1.5B or smaller** — insufficient capability for real work
- **BitNet GGUF** — broken Vulkan support, unusable CPU speed without AVX2
- **Gemma 4 uncensored variants** — incompatible chat templates

---

## VRAM Usage on RX 570 4GB

| Model | File Size | VRAM Used | Free VRAM |
|-------|-----------|-----------|-----------|
| Phi-4-mini 3.8B Q4_K_M | 2.32 GB | ~2.5 GB | ~1.5 GB |
| Llama 3.2 3B Q5_K_M | 2.16 GB | ~2.3 GB | ~1.7 GB |
| Gemma 3 4B Q4_K_M | 2.32 GB | ~2.5 GB | ~1.5 GB |
| Qwen3 4B Q4_K_M | 2.33 GB | ~2.5 GB | ~1.5 GB |

All viable models leave ~1.5 GB free for KV cache (sufficient for 4K+ context).
