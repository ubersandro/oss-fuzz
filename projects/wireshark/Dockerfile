# Copyright 2017 Google Inc.
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
RUN apt-get update && apt-get install -y ninja-build cmake libspeexdsp-dev pkg-config\
                       flex libc-ares-dev \
                       libglib2.0-dev libgcrypt20-dev wget

RUN wget https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.10.tar.xz
RUN git clone https://gitlab.com/wireshark/wireshark.git && cd wireshark && git checkout a96a1b06305653bd19ef80318f6639fe918038cd
RUN git clone https://bitbucket.org/jwzawadzki/wireshark-fuzzdb.git && cd wireshark-fuzzdb && git checkout 98fa5ba9a4c27a2fbcbe68bc43f696cfa295046e

WORKDIR wireshark
COPY build.sh $SRC/
