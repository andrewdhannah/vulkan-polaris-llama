# Root Cause Analysis: Vulkan `VK_ERROR_DEVICE_LOST` on AMD Polaris GPUs

## Summary

On AMD Polaris-family GPUs (RX 400/500 series, gfx803), llama.cpp's Vulkan backend
fails with `VK_ERROR_DEVICE_LOST` during device creation. Three independent factors
conspire to trigger this AMD driver bug.

## Factor 1: Queue Family Selection

### The Bug

The llama.cpp Vulkan backend selects **two non-graphics queue families**:
- QF 1 (compute + transfer, 2 queues)
- QF 2 (compute only, 2 queues)

On Polaris, calling `vkCreateDevice` with two queue families where **neither** has
the `VK_QUEUE_GRAPHICS_BIT` causes the driver to return `VK_ERROR_DEVICE_LOST`.

### Evidence

Systematic testing of all queue family combinations on an RX 570:

| QF Combination | Result |
|----------------|--------|
| QF 0 only (graphics + compute + transfer) | ✅ PASS |
| QF 0 + QF 1 | ✅ PASS |
| QF 0 + QF 2 | ✅ PASS |
| QF 1 only (compute + transfer) | ❌ FAIL |
| QF 2 only (compute) | ❌ FAIL |
| **QF 1 + QF 2** | **❌ FAIL** |

### The Fix

When device creation fails with the default queue selection, fall back to:
- A single queue from QF 0 (graphics-capable)
- One queue descriptor with `queueCount = 1`

This works because QF 0 on Polaris can handle compute and transfer operations even
though it has the graphics flag — the driver handles it correctly.

## Factor 2: pNext Feature Chain

### The Bug

llama.cpp queries device features using `vkGetPhysicalDeviceFeatures2` with a
pNext chain containing:
1. `VkPhysicalDeviceVulkan11Features`
2. `VkPhysicalDeviceVulkan12Features`
3. `VkPhysicalDeviceSubgroupSizeControlFeaturesEXT`
4. `VkPhysicalDeviceMaintenance4Features`
5. `VkPhysicalDevicePipelineExecutablePropertiesFeaturesKHR`

For device creation, the same pNext chain is passed to `vkCreateDevice`.
On Polaris, including the extra structs (subgroup, maintenance4, pipeline
executable properties) triggers `VK_ERROR_DEVICE_LOST` — even with a single
QF 0 queue.

### Evidence

| pNext Chain Configuration | Result |
|---------------------------|--------|
| Vk11 + Vk12 only | ✅ PASS |
| Vk11 + Vk12 + SubgroupSizeControl | ❌ FAIL |
| Vk11 + Vk12 + Maintenance4 | ❌ FAIL |
| Vk11 + Vk12 + PipelineExecutableProps | ❌ FAIL |
| Full chain (all 5) | ❌ FAIL |

### The Fix

- **Query features** with the full pNext chain (needed for capability detection)
- **Create device** with a minimal chain: `Vk11Features → Vk12Features → nullptr`
- This preserves feature detection while avoiding the driver bug in creation

## Factor 3: vulkan.hpp C++ Wrapper

### The Bug

llama.cpp uses the vulkan.hpp C++ wrapper (`vk::DeviceCreateInfo`,
`vk::PhysicalDevice::createDevice`). On the Polaris driver, the C++ wrapper
version of device creation fails silently even when the equivalent C API call
succeeds with identical parameters.

### Evidence

Direct comparison with identical queue + feature setup:

| API | Result |
|-----|--------|
| `vk::PhysicalDevice::createDevice()` | ❌ FAIL |
| `vkCreateDevice()` + `VkDeviceCreateInfo` | ✅ PASS |

### The Fix

Use pure C API (`VkDeviceCreateInfo` / `vkCreateDevice`) for device creation.
The C++ wrapper is still used for enumeration and other operations.

## Full Test Program

The test program `tests/test_vk_queues.cpp` tests all queue family combinations
and can reproduce the bug on any Polaris system:

```bash
cl test_vk_queues.cpp /I %VULKAN_SDK%\Include /link %VULKAN_SDK%\Lib\vulkan-1.lib
```

## Affected Hardware

Confirmed on:
- **GPU**: AMD Radeon RX 570 (Polaris 20, gfx803)
- **Driver**: AMD Adrenalin 26.5.2 (Vega/Polaris driver)
- **Vulkan SDK**: 1.3.296.0
- **OS**: Windows 10.0.19045

Likely affects all Polaris-family GPUs (RX 460/470/480/550/560/570/580/590)
on Windows with recent AMD drivers.

## Why This Passes on Other Vulkan Backends

- **NVIDIA**: Different queue family layout (usually single universal QF),
  different driver code path for pNext chains.
- **Intel ANV**: Similar to NVIDIA, single QF layout.
- **AMD RADV (Linux)**: The open-source Mesa driver handles these
  configurations correctly. This appears to be a Windows driver specific issue.
- **RDNA GPUs (RX 5000/6000/7000 series)**: Different driver stack
  (amdxlgpu.sys vs amdxgpuvm.sys), not affected.
