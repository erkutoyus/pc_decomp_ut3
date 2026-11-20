// iOS D3D9 read-only unbound resources. This is not Vulkan nullDescriptor
// emulation: D3D9 shaders apply SpecSamplerNull themselves. Storage nulls are
// rejected by the descriptor writer rather than redirected to shared memory.
namespace dxvk {
VkDescriptorBufferInfo DxvkUnboundResources::d3d9BufferDescriptor() {
  bufferHandle();
  auto slice = m_buffer->getSliceHandle();
  return {slice.handle, slice.offset, slice.length};
}

VkDescriptorImageInfo DxvkUnboundResources::d3d9ImageDescriptor(VkImageViewType type, bool depth) {
  if (type > VK_IMAGE_VIEW_TYPE_CUBE_ARRAY)
    throw DxvkError("UT3 D3D9: unsupported unbound image dimensionality " + std::to_string(type));
  bool volume = type == VK_IMAGE_VIEW_TYPE_3D;
  bool cube = type == VK_IMAGE_VIEW_TYPE_CUBE || type == VK_IMAGE_VIEW_TYPE_CUBE_ARRAY;
  bool line = type == VK_IMAGE_VIEW_TYPE_1D || type == VK_IMAGE_VIEW_TYPE_1D_ARRAY;
  if (depth && volume)
    throw DxvkError("UT3 D3D9: comparison sampling cannot use a 3D image");
  std::lock_guard lock(m_mutex);
  auto& view = m_d3d9Views[unsigned(type) + 7 * unsigned(depth)];
  if (view == nullptr) {
    DxvkImageCreateInfo info = {};
    info.type = volume ? VK_IMAGE_TYPE_3D : line ? VK_IMAGE_TYPE_1D : VK_IMAGE_TYPE_2D;
    info.format = depth ? VK_FORMAT_D32_SFLOAT : VK_FORMAT_R8G8B8A8_UNORM;
    info.flags = cube ? VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT : 0;
    info.sampleCount = VK_SAMPLE_COUNT_1_BIT;
    info.extent = {1, 1, 1};
    info.numLayers = cube ? 6 : 1;
    info.mipLevels = 1;
    info.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    info.stages = m_device->getShaderPipelineStages();
    info.access = VK_ACCESS_SHADER_READ_BIT;
    info.tiling = VK_IMAGE_TILING_OPTIMAL;
    info.layout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    auto image = m_device->createImage(info, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    DxvkImageViewCreateInfo vi = {};
    vi.type = type;
    vi.format = info.format;
    vi.usage = VK_IMAGE_USAGE_SAMPLED_BIT;
    vi.aspect = depth ? VK_IMAGE_ASPECT_DEPTH_BIT : VK_IMAGE_ASPECT_COLOR_BIT;
    vi.numLevels = 1;
    vi.numLayers = info.numLayers;
    view = m_device->createImageView(image, vi);
    auto ctx = m_device->createContext(DxvkContextType::Primary);
    ctx->beginRecording(m_device->createCommandList());
    VkImageSubresourceRange range = {vi.aspect, 0, 1, 0, info.numLayers};
    ctx->initImage(image, range, VK_IMAGE_LAYOUT_UNDEFINED);
    // Submit initialization before the command list that first samples it.
    m_device->submitCommandList(ctx->endRecording(), nullptr);
  }
  if (m_sampler == nullptr) {
    m_sampler = createSampler();
    m_samplerHandle.store(m_sampler->handle(), std::memory_order_release);
  }
  if (depth && m_depthSampler == nullptr) {
    DxvkSamplerCreateInfo si = {};
    si.minFilter = si.magFilter = VK_FILTER_NEAREST;
    si.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
    si.addressModeU = si.addressModeV = si.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    si.compareToDepth = VK_TRUE;
    si.compareOp = VK_COMPARE_OP_NEVER;
    si.reductionMode = VK_SAMPLER_REDUCTION_MODE_WEIGHTED_AVERAGE;
    si.maxAnisotropy = 1;
    m_depthSampler = m_device->createSampler(si);
  }
  return {depth ? m_depthSampler->handle() : m_sampler->handle(), view->handle(type), view->imageInfo().layout};
}
}
