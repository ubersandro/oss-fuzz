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

# FROM gcr.io/oss-fuzz-base/base-builder
FROM fsan-afl-codeql:latest

# Install build tools
RUN apt-get update && \
    apt-get install -y make autoconf automake groff libtool pkg-config cmake nasm autopoint && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Due to libtiff requirements, build requires autoconf 2.71 (or later)
# Can probably be removed once base-builder switches to Ubuntu 22.04
RUN curl -LO https://mirrors.edge.kernel.org/ubuntu/pool/main/a/autoconf/autoconf_2.72-3.1ubuntu1_all.deb && \
    apt install ./autoconf_2.72-3.1ubuntu1_all.deb
# DEPS.git :Little-CMS :a5b898c
# freetype :9e9d3b7
# imagemagick :2c19028
# jbigkit :4f96ddd
# 03de0ae
# 4a96b14
# libde265 :4d45a6b
# libdeflate :b122c8b
# libheif :1a3583b
# libjpeg-turbo :240e20d8
# 95156233
# 63735f74
# libjxl :d089091
# libpng :d1d0abe
# libraw :e419de0
# libtiff :1ac62678
# libwebp :ba83585
# openjpeg :402ef58
# xz :c8b8ab2
# zlib :e3dc0a8
# Clone dependencies
RUN git clone  https://github.com/imagemagick/imagemagick &&cd imagemagick && git checkout 8d1fdcb46b8a29ad1297b0925c915fd8efcb1a60
RUN git clone  https://gitlab.com/libtiff/libtiff && cd libtiff && git checkout 1ac62678
RUN git clone  https://github.com/strukturag/libde265 && cd libde265 && git checkout 4d45a6b
RUN git clone  https://github.com/strukturag/libheif && cd libheif && git checkout 1a3583b
RUN git clone  https://github.com/uclouvain/openjpeg && cd openjpeg && git checkout 402ef58
RUN git clone  https://github.com/webmproject/libwebp && cd libwebp && git checkout ba83585
RUN git clone  https://github.com/madler/zlib && cd zlib && git checkout e3dc0a8
RUN git clone  https://github.com/ebiggers/libdeflate && cd libdeflate && git checkout b122c8b
RUN git clone  https://github.com/libjpeg-turbo/libjpeg-turbo && cd libjpeg-turbo && git checkout 240e20d8
RUN git clone  https://github.com/tukaani-project/xz && cd xz && git checkout c8b8ab2
RUN git clone  https://github.com/libraw/libraw && cd libraw && git checkout 823f25d
# e419de0 
RUN git clone  https://github.com/pnggroup/libpng && cd libpng && git checkout d1d0abe
RUN git clone  https://github.com/mm2/Little-CMS && cd Little-CMS && git checkout a5b898c
RUN git clone  https://github.com/freetype/freetype && cd freetype && git checkout 9e9d3b7
RUN git clone  https://gitlab.com/federicomenaquintero/bzip2.git 
RUN git clone  --recursive https://github.com/libjxl/libjxl && cd libjxl && git checkout d089091
RUN git clone https://www.cl.cam.ac.uk/~mgk25/git/jbigkit && cd jbigkit && git checkout 4f96ddd

ADD https://lcamtuf.coredump.cx/afl/demo/afl_testcases.tgz afl_testcases.tgz

WORKDIR imagemagick
COPY build.sh run_tests.sh replay_build.sh $SRC/
