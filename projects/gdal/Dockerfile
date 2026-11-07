# Copyright 2016 Google Inc.
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

# FROM gcr.io/oss-fuzz-base/base-builder:ubuntu-24-04
FROM fsan-afl-codeql-24:latest

RUN apt-get update && \
    apt-get install -y make autoconf automake libtool g++ curl cmake sqlite3 pkg-config

RUN git clone --depth 1 https://github.com/OSGeo/gdal gdal && cd gdal && git checkout 9c765f0bdd582a2ba83f8fbf49c85dbaf4114a96 # 7f09330a48c95f3a447ad2f9ae1abe61a95ed627

RUN cp gdal/fuzzers/build.sh $SRC/

WORKDIR gdal

