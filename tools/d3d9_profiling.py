"""Opt-in timing of pinned DXVK pipeline API calls; no Vulkan argument changes."""
import re
from dxvk_source import write


def apply_pipeline_profiling(source):
    path = source / "src/dxvk/dxvk_graphics.cpp"
    text = path.read_text()
    marker = "#include <iomanip>"
    if text.count(marker) != 1:
        raise ValueError("unexpected pinned graphics header")
    text = text.replace(marker, marker + "\n#include <chrono>\n#include <cstdlib>\n#include <thread>\n#include <functional>")
    marker = "namespace dxvk {"
    helper = '''
  template<typename F> VkResult ut3ProfilePipeline(F&& create) {
    static const bool enabled = [] {
      const char* value = std::getenv("UT3_PIPELINE_TRACE");
      return value && std::string(value) == "1";
    }();
    if (!enabled) return create();
    const auto begin = std::chrono::steady_clock::now();
    const VkResult result = create();
    const auto end = std::chrono::steady_clock::now();
    const double ms = std::chrono::duration<double, std::milli>(end - begin).count();
    if (ms >= 10.0)
      Logger::info(str::format("UT3 pipeline timing: end_us=",
        std::chrono::duration_cast<std::chrono::microseconds>(end.time_since_epoch()).count(),
        " ms=", ms, " thread=", std::hash<std::thread::id>{}(std::this_thread::get_id()), " result=", result));
    return result;
  }
'''
    if text.count(marker) != 1:
        raise ValueError("unexpected pinned graphics namespace")
    text = text.replace(marker, marker + helper)
    pattern = r"VkResult vr = (vk->vkCreateGraphicsPipelines\(.*?\));"
    text, count = re.subn(pattern, r"VkResult vr = ut3ProfilePipeline([&] { return \1; });", text, flags=re.S)
    if count != 4:
        raise ValueError(f"expected four pinned graphics pipeline sites, found {count}")
    write(path, text)
