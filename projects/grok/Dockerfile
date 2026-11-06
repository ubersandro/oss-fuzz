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

RUN git clone https://github.com/GrokImageCompression/grok.git grok && cd grok && git checkout 9601176d1f5e79d8b6fd1bef26a719b98e780cec
RUN git clone https://github.com/GrokImageCompression/grok-test-data.git grok-data  && cd grok-data && git checkout 44251389d1c25a9ebcfa6564a69e90fce2a982ce
WORKDIR grok
COPY run_tests.sh build.sh $SRC/
