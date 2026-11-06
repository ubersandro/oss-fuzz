# Copyright 2020 Google Inc.
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

RUN apt-get update && apt-get install -y cmake autoconf flex bison && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN git clone  https://github.com/seladb/PcapPlusPlus PcapPlusPlus && cd PcapPlusPlus && git checkout ecfeacc

# Get tcpdump's test pcaps as seed corpusPcapPlusPlus :ecfeacc
# libpcap :0a47250
# tcpdump :d42732d
RUN git clone  https://github.com/the-tcpdump-group/tcpdump.git tcpdump && cd tcpdump && git checkout d42732d
RUN git clone  https://github.com/the-tcpdump-group/libpcap.git libpcap && cd libpcap && git checkout 0a47250

WORKDIR PcapPlusPlus

COPY *.sh pcapplusplus_enable_tests.diff $SRC/
RUN chmod +x $SRC/*.sh
