# Intro
---

### Software List

install.sh
autoconf-2.69.tar.gz
cmake-2.8.12.1.tar.gz
double-conversion-2.0.1.tar.gz
fbthrift.tar.gz
folly.tar.gz
gflags-2.1.1.tar.gz
glog-0.3.3.tar.gz
gtest-1.6.0.zip
mcrouter.tar.gz
Python-2.7.6.tar.xz

下载上述指定版本的软件，置于同一个目录。

### Install mcrouter

```bash
bash install.sh $INSTALL_DIR $CPU_NUMBERS
```
CPU_NUMBERS: default 2
INSTALL_DIR: 指定的安装目录，最后mcrouter可执行文件及相关依赖度都会安装在该目录中



