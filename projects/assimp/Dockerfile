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

# FROM gcr.io/oss-fuzz-base/base-builder
FROM fsan-afl-codeql:latest
RUN apt-get update && apt-get install -y cmake ninja-build zip && apt-get clean && rm -rf /var/lib/apt/lists/*
# RUN git clone --depth 1 --recursive https://github.com/assimp/assimp.git
# clone assimp and checkout this specific commit f0013bd3a669956903159c9f5a85ecee092d3ec5
RUN git clone --recursive https://github.com/assimp/assimp.git && cd assimp && git checkout f0013bd3a669956903159c9f5a85ecee092d3ec5
WORKDIR assimp
COPY build.sh run_tests.sh $SRC/
RUN chmod +x $SRC/build.sh $SRC/run_tests.sh
COPY fsan.blocklist.assimp $SRC/fsan.blocklist
WORKDIR /src/assimp
