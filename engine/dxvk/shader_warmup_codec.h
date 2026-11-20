#pragma once
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <vector>
#include <utility>
#include <zlib.h>

namespace ut3::shader_warmup {
constexpr size_t MaxBytes=16u<<20, MaxShaderBytes=256u<<10, MaxRecords=4096;
struct Record { bool pixel=false;std::vector<uint32_t> code; };
inline uint32_t checksum(const void *data,size_t size) {
  return uint32_t(crc32(0,static_cast<const Bytef *>(data),uInt(size)));
}
inline bool valid(const Record &record) {
  const auto &code=record.code;
  if(code.size()<2||code.size()>MaxShaderBytes/4||code[0]>>16!=(record.pixel?0xffffu:0xfffeu))return false;
  unsigned major=(code[0]>>8)&255;
  if(major<2||major>3)return false;
  for(size_t i=1;i<code.size();) {
    uint32_t token=code[i],op=token&0xffff;
    if(op==0xffff)return token==0xffff&&i+1==code.size();
    size_t count=op==0xfffe?(token>>16)&0x7fff:(token>>24)&15;
    if(count>code.size()-i-1)return false;
    i+=1+count;
  }
  return false;
}
inline void put(std::vector<uint8_t> &out,uint32_t word) {
  for(unsigned i=0;i<4;++i)out.push_back(uint8_t(word>>(8*i)));
}
inline uint32_t get(const uint8_t *data) {
  return uint32_t(data[0])|(uint32_t(data[1])<<8)|(uint32_t(data[2])<<16)|(uint32_t(data[3])<<24);
}
inline std::vector<uint8_t> encode(const std::vector<Record> &records) {
  if(records.size()>MaxRecords)return {};
  size_t bytes=0;
  for(const auto &record:records) {
    if(!valid(record)||bytes+8+record.code.size()*4>MaxBytes)return {};
    bytes+=8+record.code.size()*4;
  }
  std::vector<uint8_t> out={'U','T','3','S','H','D','R','1'};
  out.reserve(bytes+20);put(out,uint32_t(records.size()));put(out,uint32_t(bytes));put(out,0);
  for(const auto &record:records) {
    put(out,record.pixel?1:0);put(out,uint32_t(record.code.size()));
    for(uint32_t word:record.code)put(out,word);
  }
  uint32_t crc=checksum(out.data()+20,bytes);
  for(unsigned i=0;i<4;++i)out[16+i]=uint8_t(crc>>(8*i));
  return out;
}
inline bool decode(const std::vector<uint8_t> &data,std::vector<Record> &records) {
  records.clear();
  if(data.size()<20||data.size()>MaxBytes+20||memcmp(data.data(),"UT3SHDR1",8))return false;
  uint32_t count=get(data.data()+8),bytes=get(data.data()+12),crc=get(data.data()+16);
  if(count>MaxRecords||bytes!=data.size()-20||crc!=checksum(data.data()+20,bytes))return false;
  size_t cursor=20,total=0;std::vector<Record> parsed;
  for(uint32_t i=0;i<count;++i) {
    if(data.size()-cursor<8)return false;
    uint32_t stage=get(data.data()+cursor),words=get(data.data()+cursor+4);cursor+=8;
    if(stage>1||words>MaxShaderBytes/4||words>(data.size()-cursor)/4)return false;
    Record record;record.pixel=stage==1;record.code.reserve(words);
    for(uint32_t j=0;j<words;++j)record.code.push_back(get(data.data()+cursor+4*j));
    cursor+=4*words;total+=4*words;
    if(total>MaxBytes||!valid(record))return false;
    parsed.push_back(std::move(record));
  }
  if(cursor!=data.size())return false;
  records=std::move(parsed);return true;
}
}
