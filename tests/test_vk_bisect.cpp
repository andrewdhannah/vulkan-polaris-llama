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

        int compute_qf = 1, transfer_qf = 2;  // Use llama.cpp's exact families

        VkPhysicalDeviceFeatures base_features;
        vkGetPhysicalDeviceFeatures(phys_devices[i], &base_features);

        std::vector<const char*> exts = {
            "VK_KHR_maintenance4", "VK_KHR_pipeline_executable_properties",
            "VK_EXT_external_memory_host", "VK_EXT_subgroup_size_control", "VK_KHR_16bit_storage"
        };

        float priorities[] = {1.0f, 1.0f};
        std::vector<VkDeviceQueueCreateInfo> qcis;
        qcis.push_back({VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, (uint32_t)compute_qf, 1, &priorities[0]});
        qcis.push_back({VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, (uint32_t)transfer_qf, 1, &priorities[1]});

        struct TestCase {
            const char* name;
            VkBaseOutStructure* chain;
        };

        std::vector<TestCase> tests;

        // Build various chains to test

        // T1: Only Vk11+Vk12 (no extras)
        {
            static VkPhysicalDeviceVulkan12Features vk12{};
            vk12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
            static VkPhysicalDeviceVulkan11Features vk11{};
            vk11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
            vk11.pNext = &vk12;
            static VkPhysicalDeviceFeatures2 f2{};
            f2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
            f2.features = base_features;
            f2.pNext = &vk11;
            vkGetPhysicalDeviceFeatures2(phys_devices[i], &f2);
            tests.push_back({"Vk11+Vk12 only", (VkBaseOutStructure*)&f2});
        }

        // T2: Vk11+Vk12+subgroup
        {
            static VkPhysicalDeviceSubgroupSizeControlFeaturesEXT sg{};
            sg.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_SIZE_CONTROL_FEATURES_EXT;
            static VkPhysicalDeviceVulkan12Features vk12{};
            vk12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
            vk12.pNext = &sg;
            static VkPhysicalDeviceVulkan11Features vk11{};
            vk11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
            vk11.pNext = &vk12;
            static VkPhysicalDeviceFeatures2 f2{};
            f2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
            f2.features = base_features;
            f2.pNext = &vk11;
            vkGetPhysicalDeviceFeatures2(phys_devices[i], &f2);
            tests.push_back({"+subgroup", (VkBaseOutStructure*)&f2});
        }

        // T3: Vk11+Vk12+subgroup+maint4
        {
            static VkPhysicalDeviceMaintenance4Features m4{};
            m4.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_4_FEATURES;
            static VkPhysicalDeviceSubgroupSizeControlFeaturesEXT sg{};
            sg.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_SIZE_CONTROL_FEATURES_EXT;
            sg.pNext = &m4;
            static VkPhysicalDeviceVulkan12Features vk12{};
            vk12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
            vk12.pNext = &sg;
            static VkPhysicalDeviceVulkan11Features vk11{};
            vk11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
            vk11.pNext = &vk12;
            static VkPhysicalDeviceFeatures2 f2{};
            f2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
            f2.features = base_features;
            f2.pNext = &vk11;
            vkGetPhysicalDeviceFeatures2(phys_devices[i], &f2);
            tests.push_back({"+subgroup+maint4", (VkBaseOutStructure*)&f2});
        }

        // T4: Full chain (with pep)
        {
            static VkPhysicalDevicePipelineExecutablePropertiesFeaturesKHR pep{};
            pep.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PIPELINE_EXECUTABLE_PROPERTIES_FEATURES_KHR;
            static VkPhysicalDeviceMaintenance4Features m4{};
            m4.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_4_FEATURES;
            m4.pNext = &pep;
            static VkPhysicalDeviceSubgroupSizeControlFeaturesEXT sg{};
            sg.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_SIZE_CONTROL_FEATURES_EXT;
            sg.pNext = &m4;
            static VkPhysicalDeviceVulkan12Features vk12{};
            vk12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
            vk12.pNext = &sg;
            static VkPhysicalDeviceVulkan11Features vk11{};
            vk11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
            vk11.pNext = &vk12;
            static VkPhysicalDeviceFeatures2 f2{};
            f2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
            f2.features = base_features;
            f2.pNext = &vk11;
            vkGetPhysicalDeviceFeatures2(phys_devices[i], &f2);
            tests.push_back({"full chain", (VkBaseOutStructure*)&f2});
        }

        for (auto& t : tests) {
            VkDeviceCreateInfo dci{};
            dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
            dci.queueCreateInfoCount = (uint32_t)qcis.size();
            dci.pQueueCreateInfos = qcis.data();
            dci.enabledExtensionCount = (uint32_t)exts.size();
            dci.ppEnabledExtensionNames = exts.data();
            dci.pNext = t.chain;
            VkDevice device;
            res = vkCreateDevice(phys_devices[i], &dci, nullptr, &device);
            std::cout << "  " << t.name << ": " << (res == VK_SUCCESS ? "PASS" : "FAIL (DEVICE_LOST)") << std::endl;
            if (res == VK_SUCCESS) vkDestroyDevice(device, nullptr);
        }
    }

    vkDestroyInstance(instance, nullptr);
    std::cout << "Done." << std::endl;
    return 0;
}
