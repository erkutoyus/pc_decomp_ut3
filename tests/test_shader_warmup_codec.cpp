#include "../engine/dxvk/shader_warmup_codec.h"
#include <cassert>
#include <cstdio>
using namespace ut3::shader_warmup;
static void updateCrc(std::vector<uint8_t> &data) {
  uint32_t crc=checksum(data.data()+20,data.size()-20);
  for(unsigned i=0;i<4;++i)data[16+i]=uint8_t(crc>>(8*i));
}
int main() {
  Record pixel{true,{0xffff0300,0x02000001,0x800f0800,0xa0e40000,0x0000ffff}};
  Record vertex{false,{0xfffe0300,0x02000001,0xe00f0000,0x90e40000,0x0000ffff}};
  assert(valid(pixel)&&valid(vertex));
  auto bytes=encode({pixel,vertex});std::vector<Record> records;
  assert(decode(bytes,records)&&records.size()==2&&records[0].pixel&&!records[1].pixel);
  assert(records[0].code==pixel.code&&records[1].code==vertex.code);
  assert(decode(encode({}),records)&&records.empty());
  for(size_t cut=0;cut<bytes.size();++cut) {
    auto truncated=bytes;truncated.resize(cut);assert(!decode(truncated,records)&&records.empty());
  }
  for(size_t i=0;i<bytes.size();++i) {
    auto corrupted=bytes;corrupted[i]^=0x40;assert(!decode(corrupted,records)&&records.empty());
  }
  auto bad=bytes;bad[20]=2;updateCrc(bad);assert(!decode(bad,records)); // Unsupported stage with valid whole-file CRC.
  bad=bytes;for(unsigned i=0;i<4;++i)bad[24+i]=255;updateCrc(bad);assert(!decode(bad,records)); // Length overflow.
  bad=bytes;bad[31]^=1;updateCrc(bad);assert(!decode(bad,records)); // Invalid version.
  bad=bytes;bad.push_back(0);assert(!decode(bad,records));
  bad=bytes;bad[8]=255;bad[9]=255;assert(!decode(bad,records));
  auto wrong=pixel;wrong.pixel=false;assert(!valid(wrong)&&encode({wrong}).empty());
  wrong=pixel;wrong.code[0]=0xffff0104;assert(!valid(wrong)); // Existing SM1 path is not replayed.
  wrong=pixel;wrong.code[1]=0x0f000001;assert(!valid(wrong)); // Parameters extend beyond END.
  wrong=pixel;wrong.code.back()=0;assert(!valid(wrong));
  wrong=pixel;wrong.code.push_back(0xffff);assert(!valid(wrong)); // No bytes after END.
  wrong=pixel;wrong.code.resize(MaxShaderBytes/4+1);assert(!valid(wrong));
  assert(encode(std::vector<Record>(MaxRecords+1,pixel)).empty());
  assert(!decode(std::vector<uint8_t>(MaxBytes+21),records));
  puts("PASS shader warm-up codec: exact SM2/3 stage/token bounds, roundtrip, every truncation/byte corruption, checksum, record/byte limits and unsupported-version rejection");
}
