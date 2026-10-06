// SPDX-License-Identifier: Apache-2.0
// Read-only image accounting. No formatting, discard, resizing or block writes.
#include "StorageImageSizes.h"
#include <sys/system_properties.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/sysmacros.h>
#include <sys/ioctl.h>
#include <linux/fs.h>
#include <fcntl.h>
#include <unistd.h>
#include <limits.h>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <stdexcept>

struct Block {
 int fd=-1; uint64_t size=0; dev_t device=0; std::string parent;
 explicit Block(const std::string& name) {
  fd=open(("/dev/block/by-name/"+name).c_str(),O_RDONLY|O_CLOEXEC);
  if(fd<0) throw std::runtime_error("Cannot read block role "+name);
  struct stat st{}; char path[PATH_MAX],resolved[PATH_MAX];
  if(fstat(fd,&st) || !S_ISBLK(st.st_mode) || ioctl(fd,BLKGETSIZE64,&size)) {close(fd);fd=-1;throw std::runtime_error("Invalid block role "+name);}
  device=st.st_rdev;
  snprintf(path,sizeof(path),"/sys/dev/block/%u:%u",major(device),minor(device));
  if(!realpath(path,resolved)){close(fd);fd=-1;throw std::runtime_error("Cannot resolve block parent");}
  parent=resolved;parent.resize(parent.find_last_of('/'));
 }
 ~Block(){if(fd>=0)close(fd);}
 Block(const Block&)=delete;
};
static void property(const char* key,uint64_t value){
 if(__system_property_set(key,std::to_string(value).c_str()))throw std::runtime_error("Cannot publish storage measurement");
}
int main(){
 __system_property_set("sys.kiki.storage.status","unavailable");
 try {
  Block data("userdata");struct stat mounted{};struct statfs fs{};
  if(stat("/data",&mounted) || mounted.st_dev!=data.device || statfs("/data",&fs) || uint32_t(fs.f_type)!=0xf2f52010U || fs.f_bsize!=4096)throw std::runtime_error("Shared userdata mount identity mismatch");
  uint64_t dataBytes=uint64_t(fs.f_blocks)*4096;
  if(!dataBytes || dataBytes>data.size)throw std::runtime_error("Invalid userdata capacity");
  std::string disk=data.parent.substr(data.parent.find_last_of('/')+1);
  int diskFd=open(("/dev/block/"+disk).c_str(),O_RDONLY|O_CLOEXEC);uint64_t total=0;
  if(diskFd<0)throw std::runtime_error("Cannot read parent disk capacity");
  int rc=ioctl(diskFd,BLKGETSIZE64,&total);close(diskFd);
  if(rc || total<data.size)throw std::runtime_error("Invalid parent disk capacity");
  uint64_t images=0;
  for(const char* slot:{"_a","_b"})for(const char* role:{"boot","system","vendor"}){
   Block b(std::string(role)+slot);
   uint64_t budget=std::string(role)=="boot"?64ULL<<20:std::string(role)=="system"?4ULL<<30:512ULL<<20;
   if(b.parent!=data.parent || b.size!=budget)throw std::runtime_error("Unexpected physical A/B layout");
   std::array<unsigned char,4096> h{};
   if(pread(b.fd,h.data(),h.size(),0)!=ssize_t(h.size()))throw std::runtime_error("Short image header read");
   images+=std::string(role)=="boot"?kiki_storage::bootBytes(h.data(),h.size(),b.size):kiki_storage::erofsBytes(h.data(),h.size(),b.size);
  }
  if(images>total || dataBytes>total-images)throw std::runtime_error("Image/storage capacity overflow");
  property("sys.kiki.storage.disk",total);property("sys.kiki.storage.data",dataBytes);property("sys.kiki.storage.images",images);
  if(__system_property_set("sys.kiki.storage.status","ready"))throw std::runtime_error("Cannot publish ready state");
  printf("{\"diskBytes\":%llu,\"dataCapacityBytes\":%llu,\"systemImageBytes\":%llu,\"reservedPartitionBytes\":%llu}\n",(unsigned long long)total,(unsigned long long)dataBytes,(unsigned long long)images,(unsigned long long)(total-dataBytes-images));
  return 0;
 }catch(const std::exception& e){__system_property_set("sys.kiki.storage.status","unavailable");fprintf(stderr,"Storage image accounting unavailable: %s\n",e.what());return 1;}
}
