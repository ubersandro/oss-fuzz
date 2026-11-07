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

FROM fsan-afl-codeql:latest
RUN apt-get update && apt-get install -y make texinfo libgmp-dev libmpfr-dev
RUN apt-get update && apt-get install -y flex bison
RUN git clone --depth=1 https://github.com/DavidKorczynski/binary-samples binary-samples && cd binary-samples && git checkout 50f4f6ad752e982f26fab167665e763b6877c942
RUN git clone --recursive --depth 1 git://sourceware.org/git/binutils-gdb.git binutils-gdb && cd binutils-gdb && git checkout 713419a1b9adc84ce485f98e2a394bef8254c02b # 7c17eec026eb04921d86b429caeb4a7b519218e9
WORKDIR $SRC
COPY build.sh $SRC/
COPY fuzz_*.c $SRC/
COPY generate_seeds.py $SRC/
