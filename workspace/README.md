# Workspace — LLM Benchmarking & Model Management for RX 570

This directory contains the practical tooling and results from benchmarking 7 GGUF models on an AMD Radeon RX 570 4GB (Polaris gfx803) with llama.cpp.

## Contents

| File | Description |
|------|-------------|
| `benchmark_report.md` | Full benchmark results for all 7 tested models |
| `model_manager.ps1` | PowerShell script to list, switch, and manage models (callable from OpenWork) |
| `dashboard.html` | Visual dashboard showing model status and switch controls |
| `launchers/` | One-click `.bat` launchers for each model |

## Viable Models (tested & working)

| Model | File Size | Speed | Best For |
|-------|-----------|-------|----------|
| 🥇 **Phi-4-mini 3.8B Q4_K_M** | 2.32 GB | 14–51 tok/s | General use, coding, math |
| 🥈 **Llama 3.2 3B Q5_K_M** | 2.16 GB | 32–49 tok/s | Speed-sensitive tasks |
| 🥉 **Gemma 3 4B Q4_K_M** | 2.32 GB | 19–35 tok/s | Verbose, thorough responses |
| 4. **Qwen3 4B Q4_K_M** | 2.33 GB | 22–40 tok/s | Single-turn only (needs >8K context) |

## Usage

From PowerShell:
```powershell
.\model_manager.ps1 list      # List all models
.\model_manager.ps1 status    # Check current server
.\model_manager.ps1 switch phi-4   # Switch to Phi-4
.\model_manager.ps1 switch llama-3.2  # Switch to Llama 3.2
.\model_manager.ps1 stop      # Stop server
```

From OpenWork, ask the agent:
> "switch to phi-4"
> "switch to llama-3.2"

Or from the HTML dashboard, open `dashboard.html` in a browser and use the buttons.

## Hardware

- GPU: AMD Radeon RX 570 4GB (Polaris gfx803)
- CPU: Intel i5-3570K (no AVX2/FMA)
- OS: Windows 10
- Backend: llama.cpp custom build with Vulkan Polaris fix
