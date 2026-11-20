"""D3D9-only, feature-truthful fallback for the pinned iOS DXVK build.

This does not implement or advertise Vulkan robustness2. D3D9 constant and
sampler semantics are implemented explicitly; unknown writable null bindings
are rejected. The original native-feature path is left available.
"""
from build_dxvk_macos import edit
from dxvk_source import ROOT, write


def apply_d3d9_portability(source):
    adapter = "src/dxvk/dxvk_adapter.cpp"
    edit(source, adapter,
         "enabledFeatures.extRobustness2.robustBufferAccess2 = VK_TRUE;",
         "enabledFeatures.extRobustness2.robustBufferAccess2 = m_deviceFeatures.extRobustness2.robustBufferAccess2;")
    edit(source, adapter, "enabledFeatures.extRobustness2.nullDescriptor = VK_TRUE;",
         "enabledFeatures.extRobustness2.nullDescriptor = m_deviceFeatures.extRobustness2.nullDescriptor;\n"
         '    if (!enabledFeatures.extRobustness2.robustBufferAccess2 || !enabledFeatures.extRobustness2.nullDescriptor)\n'
         '      Logger::info("UT3 iOS: explicit D3D9 constant bounds and typed unbound descriptors; Vulkan robustness2 is not emulated");')
    edit(source, adapter,
         "    // Require robustBufferAccess2 since we use the robustness alignment\n"
         "    // info in a number of places, and require null descriptor support\n"
         "    // since we no longer have a fallback for those in the backend",
         "    // This iOS D3D9-only build has explicit constant bounds and typed\n"
         "    // read-only dummy descriptors. Never claim unavailable Vulkan features.")

    # DXVK's allocator creates a buffer spanning a suballocation heap. On
    # MoltenVK that Metal buffer aliases optimal textures in the same heap,
    # and buffer-to-texture upload blits violate Metal's aliasing contract.
    # Dedicated image memory preserves heap-backed image views and avoids
    # disabling MoltenVK heap/format features. Do not retry mixed allocation
    # if this correctness allocation cannot be satisfied.
    edit(source, "src/dxvk/dxvk_image.cpp",
         "      // Fill in desired memory properties",
         "      if (info.tiling == VK_IMAGE_TILING_OPTIMAL &&\n"
         "          device->properties().vk12.driverID == VK_DRIVER_ID_MOLTENVK) {\n"
         "        memoryRequirements.dedicated.prefersDedicatedAllocation = VK_TRUE;\n"
         "        memoryRequirements.dedicated.requiresDedicatedAllocation = VK_TRUE;\n"
         "      }\n\n      // Fill in desired memory properties")

    # Bound the index BEFORE OpAccessChain/OpLoad. Selecting a zero result
    # after an unsafe load does not protect adjacent constant-buffer data.
    compiler = "src/dxso/dxso_compiler.cpp"
    edit(source, compiler, "      std::array<uint32_t, 2> indices = { structIdx, relativeIdx };",
         "      uint32_t safeIdx = relativeIdx;\n"
         "      if (!m_moduleInfo.options.robustness2Supported) {\n"
         "        uint32_t count = m_module.constu32(reg.id.type == DxsoRegisterType::Const\n"
         "          ? m_layout->floatCount : m_layout->intCount);\n"
         "        uint32_t valid = m_module.opULessThan(m_module.defBoolType(), relativeIdx, count);\n"
         "        safeIdx = m_module.opSelect(m_module.defIntType(32, 0), valid, relativeIdx, m_module.constu32(0));\n"
         "      }\n"
         "      std::array<uint32_t, 2> indices = { structIdx, safeIdx };")
    edit(source, compiler, "      if (relative && !m_moduleInfo.options.robustness2Supported) {",
         "      if (!m_moduleInfo.options.robustness2Supported) {")
    edit(source, compiler, "        uint32_t constCount = m_module.constu32(m_layout->floatCount);",
         "        uint32_t constCount = m_module.constu32(reg.id.type == DxsoRegisterType::Const\n"
         "          ? m_layout->floatCount : m_layout->intCount);")
    edit(source, compiler,
         "        result.id = m_module.opSelect(typeId, cond, result.id,\n"
         "          m_module.constvec4f32(0.0f, 0.0f, 0.0f, 0.0f));",
         "        result.id = m_module.opSelect(typeId, cond, result.id, m_module.constNull(typeId));")

    # Each dimensionality and comparison mode must have its own valid
    # descriptor, including inactive branches in SM1 dynamic samplers.
    util = "src/dxso/dxso_util.h"
    edit(source, util, "  uint32_t RegisterLinkerSlot",
         '  static_assert(getSpecConstantBufferSlot() + 1 == 32, "D3D9 portability slot stride changed");\n'
         "  constexpr uint32_t getPortableSamplerSlot(uint32_t slot, uint32_t type, bool depth) {\n"
         "    return slot + (2 + 2 * type + uint32_t(depth)) * (getSpecConstantBufferSlot() + 1);\n"
         "  }\n\n  uint32_t RegisterLinkerSlot")
    edit(source, compiler,
         "m_module.decorateBinding      (sampler.varId, depth ? getShadowSamplerSlot(bindingId) : bindingId);",
         "m_module.decorateBinding      (sampler.varId, getPortableSamplerSlot(bindingId, type, depth));")
    start = "    // Store descriptor info for the shader interface\n"
    path = source / compiler
    contents = path.read_text()
    begin = contents.index(start)
    end = contents.index("\n  }", begin)
    write(path, contents[:begin] + """    // Typed slots are needed even for dynamically selected SM1 samplers.
    for (uint32_t i = 0; i < SamplerTypeCount; ++i) {
      auto samplerType = static_cast<DxsoSamplerType>(i);
      if (!implicit && samplerType != SamplerTypeFromTextureType(type)) continue;
      for (unsigned depth = 0; depth < 2; ++depth) {
        if (depth && samplerType == SamplerTypeTexture3D) continue;
        DxvkBindingInfo bindingInfo = { VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER };
        bindingInfo.resourceBinding = getPortableSamplerSlot(binding, i, depth);
        bindingInfo.viewType = samplerType == SamplerTypeTexture2D ? VK_IMAGE_VIEW_TYPE_2D
          : samplerType == SamplerTypeTexture3D ? VK_IMAGE_VIEW_TYPE_3D : VK_IMAGE_VIEW_TYPE_CUBE;
        bindingInfo.access = VK_ACCESS_SHADER_READ_BIT;
        m_bindings.push_back(bindingInfo);
      }
    }""" + contents[end:])

    device = "src/d3d9/d3d9_device.cpp"
    edit(source, device, '#include "d3d9_device.h"',
         '#include "d3d9_device.h"\n#include "../dxso/dxso_compiler.h"')
    for marker in (
        "        ctx->bindResourceSampler(stage, cSlot, Rc<DxvkSampler>(pair->second));",
        "        ctx->bindResourceSampler(stage, cSlot, Rc<DxvkSampler>(sampler));",
    ):
        value = "pair->second" if "pair->second" in marker else "sampler"
        edit(source, device, marker, marker + "\n"
             "        for (uint32_t t = 0; t < SamplerTypeCount; ++t)\n"
             "          for (unsigned d = 0; d < 2; ++d)\n"
             f"            ctx->bindResourceSampler(stage, getPortableSamplerSlot(cSlot, t, d), Rc<DxvkSampler>({value}));")
    edit(source, device, "      ctx->bindResourceImageView(stage, cSlot, std::move(cImageView));",
         "      for (uint32_t t = 0; t < SamplerTypeCount; ++t) {\n"
         "        ctx->bindResourceImageView(stage, getPortableSamplerSlot(cSlot, t, false), Rc<DxvkImageView>(cImageView));\n"
         "        ctx->bindResourceImageView(stage, getPortableSamplerSlot(cSlot, t, true), cDepth ? cImageView : nullptr);\n"
         "      }\n"
         "      ctx->bindResourceImageView(stage, cSlot, std::move(cImageView));")
    edit(source, device, "        ctx->bindResourceImageView(stage, getShadowSamplerSlot(slot), nullptr);",
         "        ctx->bindResourceImageView(stage, getShadowSamplerSlot(slot), nullptr);\n"
         "        for (uint32_t t = 0; t < SamplerTypeCount; ++t)\n"
         "          for (unsigned d = 0; d < 2; ++d)\n"
         "            ctx->bindResourceImageView(stage, getPortableSamplerSlot(slot, t, d), nullptr);", count=2)

    # Device-owned dummy objects remain live until the device is destroyed.
    edit(source, "src/dxvk/dxvk_unbound.h", "    VkSampler samplerHandle();",
         "    VkSampler samplerHandle();\n"
         "    VkDescriptorImageInfo d3d9ImageDescriptor(VkImageViewType type, bool depth);\n"
         "    VkDescriptorBufferInfo d3d9BufferDescriptor();")
    edit(source, "src/dxvk/dxvk_unbound.h", "    Rc<DxvkBuffer>          m_buffer;",
         "    Rc<DxvkBuffer>          m_buffer;\n"
         "    Rc<DxvkSampler> m_depthSampler;\n"
         "    std::array<Rc<DxvkImageView>, 14> m_d3d9Views;")
    write(source / "src/dxvk/ut3_d3d9_unbound.inc",
          (ROOT / "platform/apple/ios/d3d9_unbound.inc").read_bytes())
    edit(source, "src/dxvk/dxvk_unbound.cpp", '#include "dxvk_device.h"',
         '#include "dxvk_device.h"\n#include "dxvk_context.h"\n#include "ut3_d3d9_unbound.inc"')
    context = "src/dxvk/dxvk_context.cpp"
    edit(source, context,
         "              descriptorInfo.image.sampler = m_common->dummyResources().samplerHandle();\n"
         "              descriptorInfo.image.imageView = VK_NULL_HANDLE;\n"
         "              descriptorInfo.image.imageLayout = VK_IMAGE_LAYOUT_UNDEFINED;\n            }\n          } break;\n\n          case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:",
         "              if (m_device->features().extRobustness2.nullDescriptor) {\n"
         "                descriptorInfo.image = {m_common->dummyResources().samplerHandle(), VK_NULL_HANDLE, VK_IMAGE_LAYOUT_UNDEFINED};\n"
         "              } else {\n"
         "                constexpr uint32_t slotStride = 32;\n"
         "                bool depth = binding.resourceBinding >= 2 * slotStride\n"
         "                  && ((binding.resourceBinding / slotStride) & 1);\n"
         "                descriptorInfo.image = m_common->dummyResources().d3d9ImageDescriptor(binding.viewType, depth);\n"
         "              }\n            }\n          } break;\n\n          case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:")
    edit(source, context,
         "              descriptorInfo.buffer.buffer = VK_NULL_HANDLE;\n"
         "              descriptorInfo.buffer.offset = 0;\n"
         "              descriptorInfo.buffer.range = VK_WHOLE_SIZE;\n            }\n          } break;\n\n          case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:",
         "              descriptorInfo.buffer = m_device->features().extRobustness2.nullDescriptor\n"
         "                ? VkDescriptorBufferInfo{VK_NULL_HANDLE, 0, VK_WHOLE_SIZE}\n"
         "                : m_common->dummyResources().d3d9BufferDescriptor();\n"
         "            }\n          } break;\n\n          case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:")
    # All remaining unsupported null descriptor types must fail before any
    # Vulkan update. In particular, a shared writable dummy would be incorrect.
    edit(source, context, "      if (useDescriptorTemplates) {\n        m_cmd->updateDescriptorSetWithTemplate",
         "      if (!m_device->features().extRobustness2.nullDescriptor) {\n"
         "        for (uint32_t k = 0; k < descriptorCount; ++k) {\n"
         "          auto type = m_descriptorWrites[k].descriptorType;\n"
         "          const auto& info = m_descriptors[k];\n"
         "          bool valid = type == VK_DESCRIPTOR_TYPE_SAMPLER ? info.image.sampler != VK_NULL_HANDLE\n"
         "            : type == VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER ? info.image.imageView != VK_NULL_HANDLE && info.image.sampler != VK_NULL_HANDLE\n"
         "            : type == VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE || type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE ? info.image.imageView != VK_NULL_HANDLE\n"
         "            : type == VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER || type == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER ? info.texelBuffer != VK_NULL_HANDLE\n"
         "            : type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER || type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER ? info.buffer.buffer != VK_NULL_HANDLE : false;\n"
         '          if (!valid) throw DxvkError("UT3 D3D9: unsupported null descriptor type " + std::to_string(type));\n'
         "        }\n      }\n"
         "      if (useDescriptorTemplates) {\n        m_cmd->updateDescriptorSetWithTemplate")
    edit(source, context, "        buffers[i] = VK_NULL_HANDLE;\n        offsets[i] = 0;\n        lengths[i] = 0;",
         "        buffers[i] = m_device->features().extRobustness2.nullDescriptor\n"
         "          ? VK_NULL_HANDLE : m_common->dummyResources().bufferHandle();\n"
         "        offsets[i] = 0;\n        lengths[i] = buffers[i] ? MaxUniformBufferSize : 0;")
