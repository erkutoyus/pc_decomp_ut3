#include "shader_warmup.h"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <memory>
#include <unistd.h>
extern "C" void ut3_dxvk_host_log(const char *);

namespace ut3 {
void ShaderWarmup::log(const char *text) noexcept { ut3_dxvk_host_log(text); }
ShaderWarmup &ShaderWarmup::instance() { static ShaderWarmup cache;return cache; }
ShaderWarmup::ShaderWarmup() noexcept { try {
  const char *mode=getenv("UT3_SHADER_WARMUP"),*path=getenv("UT3_SHADER_WARMUP_CACHE");
  if(!mode||(strcmp(mode,"1")&&strcmp(mode,"learn"))||!path||!*path)return;
  m_path=path;m_replay=!strcmp(mode,"1");
  if(const char *budget=getenv("UT3_SHADER_WARMUP_MS")) {
    char *end=nullptr;unsigned long value=strtoul(budget,&end,10);
    if(end&&!*end&&value<=2000)m_budgetMs=unsigned(value);
  }
  std::unique_ptr<FILE,int(*)(FILE *)> file(fopen(m_path.c_str(),"rb"),fclose);
  if(file) {
    bool read=false;
    if(!fseek(file.get(),0,SEEK_END)) {
      long length=ftell(file.get());
      if(length>=20&&size_t(length)<=shader_warmup::MaxBytes+20&&!fseek(file.get(),0,SEEK_SET)) {
        std::vector<uint8_t> bytes(static_cast<size_t>(length));
        read=fread(bytes.data(),1,bytes.size(),file.get())==bytes.size()&&shader_warmup::decode(bytes,m_records);
      }
    }
    if(!read)log("Shader warm-up cache rejected; using original on-demand creation");
  }
  for(const auto &record:m_records) {
    m_bytes+=record.code.size()*4+8;
    m_hashes.push_back(shader_warmup::checksum(record.code.data(),record.code.size()*4));
  }
  char text[160];snprintf(text,sizeof text,"Shader warm-up: %zu cached shaders; mode=%s budget=%u ms",m_records.size(),m_replay?"replay":"learn",m_budgetMs);log(text);
  m_enabled=true;
  m_thread=std::thread([this]{writer();});
} catch(...) {
  m_enabled=false;m_records={};m_hashes={};m_bytes=0;
  log("Shader warm-up initialization unavailable; using original on-demand creation");
} }
ShaderWarmup::~ShaderWarmup() {
  {std::lock_guard<std::mutex> lock(m_mutex);m_stop=true;}
  m_cond.notify_one();if(m_thread.joinable())m_thread.join();
}
void ShaderWarmup::deviceCreated(IDirect3DDevice9 *device,uint32_t flags) noexcept {
  if(!m_enabled)return;
  if((flags&0xe0)!=D3DCREATE_HARDWARE_VERTEXPROCESSING) {
    log("Shader warm-up skipped for non-HWVP device; original shader creation retained");return;
  }
  m_device.store(device,std::memory_order_release);
  if(!m_replay||!m_budgetMs)return;
  try {
    std::vector<shader_warmup::Record> records;
    {std::lock_guard<std::mutex> lock(m_mutex);records=m_records;}
    auto start=std::chrono::steady_clock::now();size_t replayed=0,failed=0;
    for(auto it=records.rbegin();it!=records.rend();++it) {
      const auto &record=*it;
      if(replayed+failed>=1024||std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count()>=m_budgetMs)break;
      HRESULT result;
      if(record.pixel) {
        IDirect3DPixelShader9 *shader=nullptr;result=device->CreatePixelShader(record.code.data(),&shader);if(shader)shader->Release();
      } else {
        IDirect3DVertexShader9 *shader=nullptr;result=device->CreateVertexShader(record.code.data(),&shader);if(shader)shader->Release();
      }
      if(SUCCEEDED(result))++replayed;else ++failed;
    }
    char text[192];snprintf(text,sizeof text,"Shader warm-up: %zu registered, %zu failed, %.3f ms; original shader/draw calls unchanged",replayed,failed,
      std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count());log(text);
  } catch(...) {log("Shader warm-up unavailable; continuing original on-demand creation");}
}
void ShaderWarmup::forget(void *device) noexcept {
  auto expected=static_cast<IDirect3DDevice9 *>(device);
  m_device.compare_exchange_strong(expected,nullptr,std::memory_order_acq_rel);
}
void ShaderWarmup::remember(shader_warmup::Record record) {
  if(!shader_warmup::valid(record))return;
  uint32_t crc=shader_warmup::checksum(record.code.data(),record.code.size()*4);
  std::lock_guard<std::mutex> lock(m_mutex);
  for(size_t i=0;i<m_records.size();++i) {
    const auto &old=m_records[i];
    if(m_hashes[i]==crc&&old.pixel==record.pixel&&old.code==record.code) {
      if(i+1!=m_records.size()) {
        auto recent=std::move(m_records[i]);
        m_records.erase(m_records.begin()+i);m_hashes.erase(m_hashes.begin()+i);
        m_records.push_back(std::move(recent));m_hashes.push_back(crc);++m_generation;
      }
      return;
    }
  }
  // Metadata eviction changes only future warm-up; live DXVK shaders stay owned
  // by the original device cache and original game references.
  while(!m_records.empty()&&(m_records.size()>=shader_warmup::MaxRecords||m_bytes+8+record.code.size()*4>shader_warmup::MaxBytes)) {
    m_bytes-=8+m_records.front().code.size()*4;m_records.erase(m_records.begin());m_hashes.erase(m_hashes.begin());
  }
  if(m_records.size()==m_records.capacity()||m_hashes.size()==m_hashes.capacity()) {
    size_t capacity=std::min(shader_warmup::MaxRecords,std::max(size_t(16),(m_records.size()+1)*2));
    m_records.reserve(capacity);m_hashes.reserve(capacity);
  }
  m_bytes+=8+record.code.size()*4;m_records.push_back(std::move(record));m_hashes.push_back(crc);++m_generation;
}
bool ShaderWarmup::save(const std::vector<shader_warmup::Record> &records) noexcept {
  try {
    auto bytes=shader_warmup::encode(records);if(bytes.empty())return false;
    std::string part=m_path+".part";
    int fd=open(part.c_str(),O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC,0600);if(fd<0){log("Shader warm-up cache write failed");return false;}
    FILE *file=fdopen(fd,"wb");if(!file){close(fd);unlink(part.c_str());return false;}
    bool ok=fwrite(bytes.data(),1,bytes.size(),file)==bytes.size();ok=fclose(file)==0&&ok;
    if(!ok||rename(part.c_str(),m_path.c_str())){unlink(part.c_str());log("Shader warm-up cache write failed");return false;}
    char text[128];snprintf(text,sizeof text,"Shader warm-up saved: %zu shaders, %zu bytes",records.size(),bytes.size());log(text);
    return true;
  } catch(...) {log("Shader warm-up cache write unavailable");return false;}
}
void ShaderWarmup::writer() noexcept {
  try {
    std::unique_lock<std::mutex> lock(m_mutex);
    for(;;) {
      m_cond.wait_for(lock,std::chrono::seconds(2),[this]{return m_stop;});
      if(m_generation!=m_saved) {
        auto records=m_records;uint64_t generation=m_generation;
        lock.unlock();bool saved=save(records);lock.lock();if(saved)m_saved=generation;
      }
      if(m_stop)return;
    }
  } catch(...) {log("Shader warm-up writer stopped; original rendering remains active");}
}
}
