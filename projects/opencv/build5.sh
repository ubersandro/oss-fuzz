#!/bin/bash -eu
# Copyright 2018 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
################################################################################
set -x
build_dir=$WORK/build-$SANITIZER
install_dir=$WORK/install-$SANITIZER
export ASM="$CC"
mkdir -p $build_dir || rm -rf $build_dir && mkdir -p $build_dir
pushd $build_dir
cmake -D CMAKE_BUILD_TYPE=Release -D CMAKE_INSTALL_PREFIX=$install_dir \
  -DBUILD_SHARED_LIBS=OFF -DOPENCV_GENERATE_PKGCONFIG=ON \
  -DOPENCV_GENERATE_PKGCONFIG=ON -DOPENCV_FORCE_3RDPARTY_BUILD=ON \
  -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DBUILD_opencv_apps=OFF \
  -DWITH_IMGCODEC_GIF=ON -DWITH_IPP=OFF $SRC/opencv
make -j$(nproc)
make install
popd
pushd $SRC

export OPENCV_PREFIX=$install_dir
export OPENCV_MAJOR=opencv5
OPENCV_LIBS=$(ls "$OPENCV_PREFIX"/lib/libopencv_*.a)
THIRDPARTY_LIBS=$(ls "$OPENCV_PREFIX"/lib/"$OPENCV_MAJOR"/3rdparty/*.a 2>/dev/null || true)

for fuzzer in core_fuzzer filestorage_read_file_fuzzer \
   filestorage_read_filename_fuzzer filestorage_read_string_fuzzer \
   generateusergallerycollage_fuzzer imdecode_fuzzer imencode_fuzzer \
   imread_fuzzer readnetfromtensorflow_fuzzer; do
  $CXX $CXXFLAGS $LIB_FUZZING_ENGINE $fuzzer.cc -std=c++17 \
    -I"$OPENCV_PREFIX/include/$OPENCV_MAJOR" \
    -Wl,--start-group $OPENCV_LIBS $THIRDPARTY_LIBS -Wl,--end-group \
    -ldl -lm -lpthread -lrt \
    -o $OUT/$fuzzer || echo $fuzzer build failed PORCO DIO
done
popd