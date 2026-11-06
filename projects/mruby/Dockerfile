# Copyright 2019 Google Inc.
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

# FROM gcr.io/oss-fuzz-base/base-builder
FROM fsan-afl-codeql:latest
RUN apt-get update && apt-get install -y build-essential ruby bison ninja-build \
    cmake zlib1g-dev libbz2-dev liblzma-dev && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN git clone https://github.com/mruby/mruby mruby && cd mruby && git checkout 7184392b3e49bf6364c9851b9229d38a1e3f7ce1
RUN git clone --depth 1 https://github.com/bshastry/mruby_seeds.git mruby_seeds
RUN git clone https://github.com/google/libprotobuf-mutator.git && cd  libprotobuf-mutator && git checkout c1c950eae0440c3808f2b8bd7c57d0c6a42c1a90
RUN mkdir LPM; \
  cd LPM; \
  cmake $SRC/libprotobuf-mutator -GNinja -DLIB_PROTO_MUTATOR_DOWNLOAD_PROTOBUF=ON -DLIB_PROTO_MUTATOR_TESTING=OFF -DCMAKE_BUILD_TYPE=Release; \
  ninja;

COPY *.sh $SRC/
RUN chmod +x $SRC/*.sh
