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

RUN apt-get update && apt-get install -y autoconf zlibc libtool liblcms2-dev libpng-dev
RUN git clone https://github.com/apple/cups.git cups && cd cups && git checkout 0ad6ac55da2686c6fa24b05bde5e9036fd4db5d1
RUN git clone --branch VER-2-14-0 --single-branch --depth 1 https://git.savannah.gnu.org/git/freetype/freetype2.git freetype
# RUN git clone --single-branch --depth 1 git://git.ghostscript.com/ghostpdl.git ghostpdl
# RUN git clone --single-branch --depth 1 https://github.com/ArtifexSoftware/ghostpdl.git ghostpdl
RUN git init ghostpdl && cd ghostpdl && \
    git remote add origin https://github.com/ArtifexSoftware/ghostpdl.git && \
    git fetch --depth 1 origin 9d76ba026c28e08dfdf9a6866dcf87514dab935b && \
    git checkout FETCH_HEAD
RUN mkdir ghostpdl/fuzz

COPY pdf_seeds $SRC/pdf_seeds
COPY dicts $SRC/dicts

WORKDIR ghostpdl

COPY *.cc *.options *.h $SRC/
COPY build.sh generate_seeds.py $SRC/
RUN chmod +x $SRC/build.sh $SRC/generate_seeds.py