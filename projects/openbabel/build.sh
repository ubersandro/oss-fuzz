#!/bin/bash -eu
# Copyright 2021 Google LLC
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
export CXXFLAGS="${CXXFLAGS} -std=c++17"
sed -i 's/CMAKE_CXX_STANDARD 11/CMAKE_CXX_STANDARD 17/g' CMakeLists.txt
# NOTE: build at O2, not O3
# build project
mkdir build && cd build
# build rel with dbg info
cmake .. -DCMAKE_VERBOSE_MAKEFILE=ON -DBUILD_SHARED=OFF -DBUILD_MIXED=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_CXX_FLAGS_RELWITHDEBINFO="${CXXFLAGS}"
make -j $(nproc) VERBOSE=1
cp bin/fuzz* $OUT/

