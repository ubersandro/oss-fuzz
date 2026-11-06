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

FROM fsan-afl-codeql:latest
# LLVM is a piece of SH with types
ENV HWASAN_OPTIONS=symbolize=0:exitcode=0:halt_on_error=0:abort_on_error=0:recover_report=summary:verbosity=0:detect_leaks=0:allocator_may_return_null=1 
RUN apt-get update -y && \
    apt-get install -y autoconf automake libtool curl make g++ unzip wget git \
    binutils liblzma-dev libz-dev python-all cmake ninja-build subversion \
    pkg-config

RUN git clone https://github.com/llvm/llvm-project.git && cd llvm-project && git checkout f598a65ebafc92aace3cc475f0df640fc5bfd71a

RUN git clone https://github.com/AdaLogics/ada-fuzzers && cd ada-fuzzers && git checkout 87026e03ca7404dd3fa7f1b3f7726b917daa743e && \
    $SRC/ada-fuzzers/projects/llvm/copy-over.sh

COPY build.sh *.py $SRC/
