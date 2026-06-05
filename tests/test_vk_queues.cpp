#define VK_USE_PLATFORM_WIN32_KHR
#include <vulkan/vulkan.h>
#include <iostream>
#include <vector>
#include <cstring>

int main() {
    uint32_t api_version = VK_API_VERSION_1_2;
    PFN_vkEnumerateInstanceVersion pfn = (PFN_vkEnumerateInstanceVersion)vkGetInstanceProcAddr(nullptr, "vkEnumerateInstanceVersion");
    if (pfn) pfn(&api_version);

    VkApplicationInfo app_info{};
    app_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = "Test";
    app_info.apiVersion = api_version;

    VkInstanceCreateInfo inst_info{};
    inst_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    inst_info.pApplicationInfo = &app_info;

    VkInstance instance;
    VkResult res = vkCreateInstance(&inst_info, nullptr, &instance);
    if (res != VK_SUCCESS) return 1;

    uint32_t dev_count = 0;
    vkEnumeratePhysicalDevices(instance, &dev_count, nullptr);
    std::vector<VkPhysicalDevice> phys_devices(dev_count);
    vkEnumeratePhysicalDevices(instance, &dev_count, phys_devices.data());

    for (uint32_t i = 0; i < dev_count; i++) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(phys_devices[i], &props);
        std::cout << "Device: " << props.deviceName << std::endl;

        uint32_t qf_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(phys_devices[i], &qf_count, nullptr);
        std::vector<VkQueueFamilyProperties> qf_props(qf_count);
        vkGetPhysicalDeviceQueueFamilyProperties(phys_devices[i], &qf_count, qf_props.data());

        VkPhysicalDeviceFeatures base_features;
        vkGetPhysicalDeviceFeatures(phys_devices[i], &base_features);

        // 5 extensions, Vk11+Vk12 chain (no extras)
        std::vector<const char*> exts = {
            "VK_KHR_maintenance4", "VK_KHR_pipeline_executable_properties",
            "VK_EXT_external_memory_host", "VK_EXT_subgroup_size_control", "VK_KHR_16bit_storage"
        };

        // Test 1: Single queue family (qf 0, 1 queue)
        {
            VkPhysicalDeviceVulkan12Features vk12{};
            vk12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
            VkPhysicalDeviceVulkan11Features vk11{};
            vk11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
            vk11.pNext = &vk12;
            VkPhysicalDeviceFeatures2 f2{};
            f2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
            f2.features = base_features;
            f2.pNext = &vk11;
            vkGetPhysicalDeviceFeatures2(phys_devices[i], &f2);

            float priority = 1.0f;
            VkDeviceQueueCreateInfo qci{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, 0, 1, &priority};
            VkDeviceCreateInfo dci{};
            dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
            dci.queueCreateInfoCount = 1;
            dci.pQueueCreateInfos = &qci;
            dci.enabledExtensionCount = (uint32_t)exts.size();
            dci.ppEnabledExtensionNames = exts.data();
            dci.pNext = &f2;
            VkDevice device;
            res = vkCreateDevice(phys_devices[i], &dci, nullptr, &device);
            std::cout << "  Single QF0: " << (res == VK_SUCCESS ? "PASS" : "FAIL (DEVICE_LOST)") << std::endl;
            if (res == VK_SUCCESS) vkDestroyDevice(device, nullptr);
        }

        // Test 2: Two queue families (qf 0 + qf 1)
        {
            VkPhysicalDeviceVulkan12Features vk12{};
            vk12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
            VkPhysicalDeviceVulkan11Features vk11{};
            vk11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
            vk11.pNext = &vk12;
            VkPhysicalDeviceFeatures2 f2{};
            f2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
            f2.features = base_features;
            f2.pNext = &vk11;
            vkGetPhysicalDeviceFeatures2(phys_devices[i], &f2);

            float priorities[] = {1.0f, 1.0f};
            VkDeviceQueueCreateInfo qcis[2] = {
                {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, 0, 1, &priorities[0]},
                {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, 1, 1, &priorities[1]}
            };
            VkDeviceCreateInfo dci{};
            dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
            dci.queueCreateInfoCount = 2;
            dci.pQueueCreateInfos = qcis;
            dci.enabledExtensionCount = (uint32_t)exts.size();
            dci.ppEnabledExtensionNames = exts.data();
            dci.pNext = &f2;
            VkDevice device;
            res = vkCreateDevice(phys_devices[i], &dci, nullptr, &device);
            std::cout << "  Dual QF0+QF1: " << (res == VK_SUCCESS ? "PASS" : "FAIL (DEVICE_LOST)") << std::endl;
            if (res == VK_SUCCESS) vkDestroyDevice(device, nullptr);
        }

        // Test 3: Two queue families (qf 0 + qf 2)
        {
            VkPhysicalDeviceVulkan12Features vk12{};
            vk12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
            VkPhysicalDeviceVulkan11Features vk11{};
            vk11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
            vk11.pNext = &vk12;
            VkPhysicalDeviceFeatures2 f2{};
            f2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
            f2.features = base_features;
            f2.pNext = &vk11;
            vkGetPhysicalDeviceFeatures2(phys_devices[i], &f2);

            float priorities[] = {1.0f, 1.0f};
            VkDeviceQueueCreateInfo qcis[2] = {
                {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, 0, 1, &priorities[0]},
                {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, 2, 1, &priorities[1]}
            };
            VkDeviceCreateInfo dci{};
            dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
            dci.queueCreateInfoCount = 2;
            dci.pQueueCreateInfos = qcis;
            dci.enabledExtensionCount = (uint32_t)exts.size();
            dci.ppEnabledExtensionNames = exts.data();
            dci.pNext = &f2;
            VkDevice device;
            res = vkCreateDevice(phys_devices[i], &dci, nullptr, &device);
            std::cout << "  Dual QF0+QF2: " << (res == VK_SUCCESS ? "PASS" : "FAIL (DEVICE_LOST)") << std::endl;
            if (res == VK_SUCCESS) vkDestroyDevice(device, nullptr);
        }

        // Test 4: Two queue families (qf 1 + qf 2) ? exact llama.cpp
        {
            VkPhysicalDeviceVulkan12Features vk12{};
            vk12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
            VkPhysicalDeviceVulkan11Features vk11{};
            vk11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
            vk11.pNext = &vk12;
            VkPhysicalDeviceFeatures2 f2{};
            f2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
            f2.features = base_features;
            f2.pNext = &vk11;
            vkGetPhysicalDeviceFeatures2(phys_devices[i], &f2);

            float priorities[] = {1.0f, 1.0f};
            VkDeviceQueueCreateInfo qcis[2] = {
                {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, 1, 1, &priorities[0]},
                {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, 2, 1, &priorities[1]}
            };
            VkDeviceCreateInfo dci{};
            dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
            dci.queueCreateInfoCount = 2;
            dci.pQueueCreateInfos = qcis;
            dci.enabledExtensionCount = (uint32_t)exts.size();
            dci.ppEnabledExtensionNames = exts.data();
            dci.pNext = &f2;
            VkDevice device;
            res = vkCreateDevice(phys_devices[i], &dci, nullptr, &device);
            std::cout << "  Dual QF1+QF2 (llama): " << (res == VK_SUCCESS ? "PASS" : "FAIL (DEVICE_LOST)") << std::endl;
            if (res == VK_SUCCESS) vkDestroyDevice(device, nullptr);
        }
    }

    vkDestroyInstance(instance, nullptr);
    std::cout << "Done." << std::endl;
    return 0;
}
