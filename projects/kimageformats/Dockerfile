
# Copyright 2018 Google Inc.
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
FROM fsan-afl:latest
RUN git clone -b master https://invent.kde.org/frameworks/kimageformats.git && cd kimageformats && git checkout 215305f
# COPY ./prepare_build.sh $SRC/kimageformats/autotests/ossfuzz/

# RUN chmod +x $SRC/kimageformats/autotests/ossfuzz/prepare_build.sh && $SRC/kimageformats/autotests/ossfuzz/prepare_build.sh
#!/bin/bash -eu
#
# SPDX-FileCopyrightText: 2018 Google Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Based on https://github.com/google/oss-fuzz/blob/33aab4a70dc4b5811143d214536584a8c8cb3924/projects/kimageformats/Dockerfile
# Copyright 2018 Google Inc.
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

RUN apt-get update && \
    apt-get install -y cmake make autoconf automake autopoint libtool \
    wget po4a ninja-build pkgconf

RUN git clone  https://github.com/madler/zlib.git && cd zlib && git checkout e3dc0a8 
RUN git clone  -b v1.5.7 https://github.com/facebook/zstd.git && cd zstd && git checkout f8745da
RUN wget https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
RUN git clone  https://github.com/tukaani-project/xz.git && cd xz && git checkout c8b8ab2e
RUN git clone  --branch=RB-3.4 https://github.com/AcademySoftwareFoundation/openexr.git && cd openexr && git checkout ca50a6b
RUN git clone  -b master https://invent.kde.org/frameworks/extra-cmake-modules.git && cd extra-cmake-modules && git checkout 18cd7d1
RUN git clone  --branch=dev git://code.qt.io/qt/qtbase.git && cd qtbase && git checkout a31df331
RUN git clone  --branch=dev git://code.qt.io/qt/qttools.git && cd qttools && git checkout 250a111
RUN git clone  -b master https://invent.kde.org/frameworks/karchive.git && cd karchive && git checkout f17447d
RUN git clone  -b v3.15.0 https://aomedia.googlesource.com/aom && cd aom && git checkout 0308786
RUN git clone  -b v1.4.2 https://github.com/AOMediaCodec/libavif.git && cd libavif && git checkout c5240fc
RUN git clone  https://github.com/strukturag/libde265.git && cd libde265 && git checkout 4d45a6b
RUN git clone  -b v2.5.4 https://github.com/uclouvain/openjpeg.git && cd openjpeg && git checkout 6c4a29b
RUN git clone  https://github.com/strukturag/libheif.git && cd libheif && git checkout 1a3583b
RUN git clone --recursive --shallow-submodules https://github.com/libjxl/libjxl.git && cd libjxl && git checkout d089091
RUN git clone  https://github.com/LibRaw/LibRaw && cd LibRaw && git checkout e419de0
RUN git clone  https://github.com/mircomir/jxrlib.git && cd jxrlib && git checkout fdf6bc4
RUN git clone  -b v2.6.0 https://github.com/cisco/openh264.git && cd openh264 && git checkout 652bdb7


RUN cp $SRC/kimageformats/autotests/ossfuzz/build_fuzzers.sh $SRC/build.sh
RUN chmod +x $SRC/build.sh
WORKDIR $SRC/kimageformats
# initialize blocklist to 
# class.QUninitialized
# struct.QHashPrivate::Span
# struct.QMetaObject::Data
# StaticContent*
# QColorMatrix
# QColorVector
RUN echo "class.QUninitialized\nstruct.QHashPrivate::Span\nstruct.QMetaObject::Data\nStaticContent*\nQColorMatrix\nQColorVector" > $SRC/fsan.blocklist
