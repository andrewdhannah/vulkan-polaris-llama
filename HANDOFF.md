# 🚀 Project Handoff: Vulkan Polaris Accelerator

## 🛠 Hardware Environment
- **CPU:** Intel Core i5-3570K (Ivy Bridge, **AVX only** — no AVX2/FMA).
- **GPU:** AMD Radeon RX 570 (4GB VRAM, Polaris/gfx803).
- **OS:** Windows 10.
- **Vulkan SDK:** 1.3.296.0.

## ⚠️ Critical Vulkan Bug Fix (Polaris)
Standard llama.cpp Vulkan builds trigger `VK_ERROR_DEVICE_LOST` on Polaris GPUs. This was resolved by implementing three specific changes in `ggml-vulkan.cpp`:
1. **Queue Families:** Force fallback to a single **QF 0** (graphics-capable) queue. Combining non-graphics queues (QF 1 + QF 2) crashes the driver.
2. **pNext Chain:** Stripped the `vkCreateDevice` chain to **Vk11 + Vk12** only. Including extra feature structs (SubgroupSize, Maintenance4, etc.) triggers the driver bug.
3. **C API:** Switched from `vk::PhysicalDevice::createDevice` (C++ wrapper) to raw `vkCreateDevice` (C API).

## 🌐 Server Configuration
A custom lightweight C++ server (`llama-server-mini.exe`) was implemented to provide an OpenAI-compatible API for remote access.

- **Default Port:** `8080`
- **Base URL:** `http://<WINDOWS_IP>:8080/v1`
- **Provider Setup:** Add as "Custom OpenAI-compatible" in OpenWork.

## 🧠 Current Model Setup
- **Model:** `Qwen2.5-MOE-2X1.5B-DeepSeek-Uncensored-Censored-4B-D_AU-Q4_k_m.gguf`
- **Architecture:** Mixture of Experts (MoE).
- **Optimized Params:**
  - `-ngl 20` (Partial offload to avoid VRAM overflow).
  - `-c 8192` (Safe context window).
  - `-ctk q8_0` / `-ctv q8_0` (Quantized KV cache for memory efficiency).

## 📂 File Locations
- **Build Directory:** `G:\llama.cpp\build_vs\`
- **Project Repo:** `G:\vulkan-polaris-llama\` (Mirrored to `github.com/andrewdhannah/vulkan-polaris-llama`)
- **Launcher:** `G:\llama.cpp\start_server.bat`

## 🚩 Next Steps / Pending
- Verify stability of the MoE model over long-duration agentic loops.
- Further optimize `-ngl` (GPU layer) count based on actual VRAM usage during high-context turns.
