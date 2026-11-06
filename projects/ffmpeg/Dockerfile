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

# FROM gcr.io/oss-fuzz-base/base-builder
FROM fsan-afl-codeql:latest
RUN apt-get update && apt-get install -y nasm pkg-config rsync libtool gperf help2man && apt-get clean && rm -rf /var/lib/apt/lists/*
# RUN curl -LO https://mirrors.kernel.org/ubuntu/pool/main/a/automake-1.16/automake_1.16.5-1.3_all.deb && \
#     apt install ./automake_1.16.5-1.3_all.deb
RUN set -e; deb=automake_1.16.5-1.3_all.deb; \
    for m in https://mirrors.edge.kernel.org/ubuntu http://archive.ubuntu.com/ubuntu \
             http://de.archive.ubuntu.com/ubuntu https://mirror.math.princeton.edu/pub/ubuntu; do \
        curl -fL --retry 3 --connect-timeout 15 -o "$deb" "$m/pool/main/a/automake-1.16/$deb" && break; \
    done; \
    echo "59e3890fc8407bcf8ccc9f709d6513156346d5c942e8c624dc90435e58f6f978  $deb" | sha256sum -c -; \
    apt-get install -y "./$deb"; rm -f "$deb"
RUN curl -LO https://mirrors.kernel.org/ubuntu/pool/main/a/autoconf/autoconf_2.72-3.1ubuntu1_all.deb && \
    apt install ./autoconf_2.72-3.1ubuntu1_all.deb
RUN python3 -m pip install --upgrade pip && python3 -m pip install -U meson==1.11.1 ninja

RUN git clone  https://github.com/FFmpeg/FFmpeg ffmpeg && cd ffmpeg && git checkout 98e45d6
# REPLACE char reserved_internal_buffer[1]; with char reserved_internal_buffer[1004]; in file libavutil/bprint.h
# RUN sed -i 's/char reserved_internal_buffer\[1\];/char reserved_internal_buffer[1004];/' ffmpeg/libavutil/bprint.h
# patch needed for 
# bzip2 :bf905ea
# fdk-aac :d8e6b1a
# ffmpeg :98e45d6
# fontconfig :d32a191
# freetype :9e9d3b7
# fribidi :ee2edf7
# harfbuzz :d8dabe2
# libass :3087d2b
# libvpx :9cc8e1c
# libxml2 :c632489
# ogg :06a5e02
# opus :3da9f7a
# theora :28fd5ec
# vorbis :1b75110
# zlib :e3dc0a8
RUN curl -O https://www.alsa-project.org/files/pub/lib/alsa-lib-1.2.12.tar.bz2
RUN git clone  https://github.com/mstorsjo/fdk-aac.git && cd fdk-aac && git checkout d8e6b1a
RUN git clone  https://gitlab.freedesktop.org/fontconfig/fontconfig.git && cd fontconfig && git checkout d32a191
RUN git clone  https://gitlab.freedesktop.org/freetype/freetype.git && cd freetype && git checkout 9e9d3b7
RUN git clone  https://github.com/fribidi/fribidi && cd fribidi && git checkout ee2edf7
RUN git clone  https://github.com/harfbuzz/harfbuzz && cd harfbuzz && git checkout d8dabe2
RUN git clone  https://github.com/libass/libass && cd libass && git checkout 3087d2b
RUN git clone  https://github.com/madler/zlib && cd zlib && git checkout e3dc0a8
RUN git clone https://gitlab.com/federicomenaquintero/bzip2 && cd bzip2 && git checkout bf905ea
RUN git clone  https://chromium.googlesource.com/webm/libvpx && cd libvpx && git checkout 9cc8e1c
RUN git clone  https://gitlab.xiph.org/xiph/ogg.git && cd ogg && git checkout 06a5e02
RUN git clone  https://gitlab.xiph.org/xiph/opus.git && cd opus && git checkout 3da9f7a
RUN git clone  https://gitlab.xiph.org/xiph/theora.git && cd theora && git checkout 28fd5ec
RUN git clone  https://gitlab.xiph.org/xiph/vorbis.git && cd vorbis && git checkout 1b75110
RUN git clone  https://gitlab.gnome.org/GNOME/libxml2.git && cd libxml2 && git checkout c632489

COPY build.sh replay_build.sh run_tests.sh group_seed_corpus.py name_mappings.py $SRC/
RUN chmod +x $SRC/build.sh $SRC/replay_build.sh $SRC/run_tests.sh