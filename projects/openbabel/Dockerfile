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
# force build at O2, NOT O3
# FROM gcr.io/oss-fuzz-base/base-builder
FROM fsan-afl
RUN apt-get update && apt install -y  && apt-get clean && rm -rf /var/lib/apt/lists/*
# EVAL FSAN COMMIT : b3c041ad759bd25a7ef2925bbf0da8426a6d15f6
RUN git clone https://github.com/openbabel/openbabel.git
RUN cd openbabel && git checkout b3c041ad759bd25a7ef2925bbf0da8426a6d15f6
RUN rm -rf /openbabel/.git

COPY *.sh $SRC/
WORKDIR $SRC/openbabel
CMD ["/bin/bash"]