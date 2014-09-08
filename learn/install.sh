#!/usr/bin/env bash
# vim:fileencoding=UTF-8

# FileName: install.sh
# Created:  11月 12, 2014
# Author(s): Xu Guojun <qinguan0619@qiyi.com>

# checked under ubuntu14.04

set -ex
die() { printf "%s: %s\n" "$0" "$@"; exit 1; }
[ -n "$1" ] || die "INSTALL_DIR missing"

:<<!
============================================================================================
install pre
!

sudo apt-get update

sudo apt-get install -y gcc-4.8 g++-4.8 libboost1.54-dev libboost-thread1.54-dev \
    libboost-filesystem1.54-dev libboost-system1.54-dev libboost-regex1.54-dev \
    libboost-python1.54-dev libboost-context1.54-dev ragel autoconf unzip \
    libsasl2-dev git libtool python-dev cmake libssl-dev libcap-dev libevent-dev \
    libgtest-dev libsnappy-dev scons flex bison libkrb5-dev binutils-dev make \
    libnuma-dev

sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.8 50
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-4.8 50



:<<!
============================================================================================
install gflags
!

ROOT_DIR=$1

PKG_DIR=$ROOT_DIR/pkgs
INSTALL_DIR=$ROOT_DIR/install
MAKE_ARGS="-j2"
#REQUIRED_SOFT_DIR=/root/download/pre/mcrouter/required_soft
REQUIRED_SOFT_DIR=$(cd $(dirname "$0") && pwd)

mkdir -p "$PKG_DIR" "$INSTALL_DIR"

cd $PKG_DIR
cp "$REQUIRED_SOFT_DIR"/gflags-2.1.1.tar.gz .
tar xzvf gflags-2.1.1.tar.gz
mkdir -p gflags-2.1.1/build/ && cd gflags-2.1.1/build/

cp "$REQUIRED_SOFT_DIR"/cmake-2.8.12.1.tar.gz .
tar xzvf cmake-2.8.12.1.tar.gz
cd cmake-2.8.12.1
cmake . && make
cd ..
CMAKE=./cmake-2.8.12.1/bin/cmake

$CMAKE .. -DBUILD_SHARED_LIBS:BOOL=ON \
    -DCMAKE_INSTALL_PREFIX:PATH="$INSTALL_DIR" \
    -DGFLAGS_NAMESPACE:STRING=google && make $MAKE_ARGS && make install $MAKE_ARGS
	
:<<!
============================================================================================
install glogs
!

cd $PKG_DIR
cp "$REQUIRED_SOFT_DIR"/glog-0.3.3.tar.gz .
tar xzvf glog-0.3.3.tar.gz
cd glog-0.3.3
LDFLAGS="-Wl,-rpath=$INSTALL_DIR/lib,--enable-new-dtags -L$INSTALL_DIR/lib" \
    CPPFLAGS="-I$INSTALL_DIR/include" \
    ./configure --prefix="$INSTALL_DIR" && make $MAKE_ARGS && make install $MAKE_ARGS
	
:<<!
============================================================================================
install folly
!
	
cd $PKG_DIR
[ -d folly ] || cp "$REQUIRED_SOFT_DIR"/folly.tar.gz . && tar -zxvf folly.tar.gz

mkdir -p double-conversion && cd double-conversion
cp "$REQUIRED_SOFT_DIR"/double-conversion-2.0.1.tar.gz .

tar xzvf double-conversion-2.0.1.tar.gz
cp "$PKG_DIR/folly/folly/SConstruct.double-conversion" .
scons -f SConstruct.double-conversion

# Folly looks for double-conversion/double-conversion.h
ln -sf src double-conversion
# Folly looks for -ldouble-conversion (dash, not underscore)
# Must be PIC, since folly also builds a shared library
ln -sf libdouble_conversion_pic.a libdouble-conversion.a

cd "$PKG_DIR/folly/folly/test/"
cp "$REQUIRED_SOFT_DIR"/gtest-1.6.0.zip .
unzip -o gtest-1.6.0.zip

cd "$PKG_DIR/folly/folly/"

autoreconf --install
LD_LIBRARY_PATH="$INSTALL_DIR/lib:$LD_LIBRARY_PATH" \
    LD_RUN_PATH="$INSTALL_DIR/lib" \
    LDFLAGS="-L$INSTALL_DIR/lib -L$PKG_DIR/double-conversion -ldl" \
    CPPFLAGS="-I$INSTALL_DIR/include -I$PKG_DIR/double-conversion" \
    ./configure --prefix="$INSTALL_DIR" && make $MAKE_ARGS && make install $MAKE_ARGS

:<<!
============================================================================================
install fbthrift
!
cd "$PKG_DIR"
[ -d fbthrift ] || cp "$REQUIRED_SOFT_DIR"/fbthrift.tar.gz . && tar -zxvf fbthrift.tar.gz
cd fbthrift/thrift
# Fix build
sed 's/PKG_CHECK_MODULES.*$/true/g' -i configure.ac
ln -sf thrifty.h "$PKG_DIR/fbthrift/thrift/compiler/thrifty.hh"

autoreconf --install
# LD_LIBRARY_PATH is needed since configure builds small programs with -lgflags, and doesn't use
# libtool to encode full library path, so running those will not find libgflags otherwise
# We need --enable-boostthreads, since otherwise thrift will not link against
# -lboost_thread, while still using functions from it (need to fix thrift directly)
LD_LIBRARY_PATH="$INSTALL_DIR/lib:$LD_LIBRARY_PATH" \
    LD_RUN_PATH="$INSTALL_DIR/lib" \
    LDFLAGS="-L$INSTALL_DIR/lib" \
    CPPFLAGS="-I$INSTALL_DIR/include -I$INSTALL_DIR/include/python2.7 -I$PKG_DIR/folly -I$PKG_DIR/double-conversion" \
    ./configure --prefix=$INSTALL_DIR --enable-boostthreads
cd "$PKG_DIR/fbthrift/thrift/" && make clean
cd "$PKG_DIR/fbthrift/thrift/compiler" && make $MAKE_ARGS
cd "$PKG_DIR/fbthrift/thrift/lib/thrift" && make $MAKE_ARGS
cd "$PKG_DIR/fbthrift/thrift/lib/cpp2" && make gen-cpp2/Sasl_types.h $MAKE_ARGS
cd "$PKG_DIR/fbthrift/thrift/lib/cpp2/test" && make gen-cpp2/Service_constants.cpp $MAKE_ARGS
cd "$PKG_DIR/fbthrift/thrift" && make $MAKE_ARGS && sudo make install $MAKE_ARGS

:<<!
============================================================================================
install mcrouter
!

cd "$PKG_DIR"
cp "$REQUIRED_SOFT_DIR"/mcrouter.tar.gz . && tar -zxvf mcrouter.tar.gz && cd mcrouter/mcrouter/

autoreconf --install
LD_LIBRARY_PATH="$INSTALL_DIR/lib:$LD_LIBRARY_PATH" \
    LD_RUN_PATH="$PKG_DIR/folly/folly/test/.libs:$INSTALL_DIR/lib" \
    LDFLAGS="-L$PKG_DIR/folly/folly/test/.libs -L$INSTALL_DIR/lib" \
    CPPFLAGS="-I$PKG_DIR/folly/folly/test/gtest-1.6.0/include -I$INSTALL_DIR/include -I$PKG_DIR/folly -I$PKG_DIR/fbthrift -I$PKG_DIR/double-conversion" \
    ./configure --prefix="$INSTALL_DIR"
# Need to find ragel
PATH="$INSTALL_DIR/bin:$PATH" make $MAKE_ARGS
make install $MAKE_ARGS






