#pragma once
#include <d3d9.h>
#include <atomic>
#include <condition_variable>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include "shader_warmup_codec.h"

namespace ut3 {
class ShaderWarmup {
public:
  static ShaderWarmup &instance();
  void deviceCreated(IDirect3DDevice9 *device,uint32_t flags) noexcept;
  void forget(void *device) noexcept;
  template<typename Shader> void record(IDirect3DDevice9 *device,Shader *shader,bool pixel) noexcept {
    if(!shader||!m_enabled||m_device.load(std::memory_order_acquire)!=device)return;
    try {
      UINT bytes=0;
      if(FAILED(shader->GetFunction(nullptr,&bytes))||bytes<8||bytes>shader_warmup::MaxShaderBytes||bytes%4)return;
      shader_warmup::Record record;record.pixel=pixel;record.code.resize(bytes/4);
      if(FAILED(shader->GetFunction(record.code.data(),&bytes))||bytes!=record.code.size()*4)return;
      remember(std::move(record));
    } catch(...) { log("Shader warm-up record unavailable; original shader retained"); }
  }
private:
  ShaderWarmup() noexcept;
  ~ShaderWarmup();
  void remember(shader_warmup::Record record);
  void writer() noexcept;
  bool save(const std::vector<shader_warmup::Record> &records) noexcept;
  static void log(const char *text) noexcept;
  bool m_enabled=false,m_replay=false,m_stop=false;
  unsigned m_budgetMs=500;
  std::atomic<IDirect3DDevice9 *> m_device{};
  std::string m_path;
  std::mutex m_mutex;
  std::condition_variable m_cond;
  std::thread m_thread;
  std::vector<shader_warmup::Record> m_records;
  std::vector<uint32_t> m_hashes;
  size_t m_bytes=0;
  uint64_t m_generation=0,m_saved=0;
};
}
