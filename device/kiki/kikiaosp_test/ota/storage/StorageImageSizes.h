// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <stdexcept>
namespace kiki_storage {
inline uint32_t le32(const unsigned char* h, size_t at) {
 return uint32_t(h[at]) | uint32_t(h[at+1])<<8 | uint32_t(h[at+2])<<16 | uint32_t(h[at+3])<<24;
}
inline uint64_t bootBytes(const unsigned char* h, size_t n, uint64_t capacity) {
 if(n<4096 || std::memcmp(h,"ANDROID!",8) || le32(h,40)!=4 || le32(h,20)!=1584 || le32(h,1580)!=0 || !le32(h,8)) throw std::runtime_error("Invalid unsigned header-v4 boot image");
 auto align=[](uint64_t x){return (x+4095)&~uint64_t(4095);};
 uint64_t bytes=4096+align(le32(h,8))+align(le32(h,12));
 if(bytes>capacity) throw std::runtime_error("Boot image exceeds partition");
 return bytes;
}
inline uint64_t erofsBytes(const unsigned char* h, size_t n, uint64_t capacity) {
 if(n<4096 || le32(h,1024)!=0xe0f5e1e2 || h[1036]!=12 || (le32(h,1104)&0x80)) throw std::runtime_error("Unsupported EROFS image header");
 uint64_t bytes=uint64_t(le32(h,1060))*4096;
 if(bytes<4096 || bytes>capacity) throw std::runtime_error("EROFS size exceeds partition");
 return bytes;
}
}
