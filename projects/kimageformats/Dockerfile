
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
RUN touch $SRC/fsan.blocklist
# also uninstrument variable QMetaObjectStatic -> in the src code of the compiler

RUN git clone -b master https://invent.kde.org/frameworks/kimageformats.git
RUN cd kimageformats && git checkout 215305f
RUN rm -rf kimageformats/.git
COPY kimageformats.blocklist $SRC/fsan.blocklist
RUN $SRC/kimageformats/autotests/ossfuzz/prepare_build.sh
RUN cp $SRC/kimageformats/autotests/ossfuzz/build_fuzzers.sh $SRC/build.sh
# patch the build to remove their LDFLAGS -> comment out lines from 21 to 25, including extremes
RUN sed -i '21,25 s/^/#/' $SRC/build.sh
RUN chmod +x $SRC/build.sh
WORKDIR $SRC/kimageformats

# PATCH for libde265
# insert this line after Build libde265 -> # export CFLAGS="${CFLAGS/-O2/-O1}" ;export CXXFLAGS="${CXXFLAGS/-O2/-O1}", do not replace, insert in place
# RUN sed -i 's/Build libde265/&\nexport CFLAGS="${CFLAGS/-O2/-O1}" ;export CXXFLAGS="${CXXFLAGS/-O2/-O1}"/' $SRC/build.sh
# before Build openjpeg, restore CFLAGS and CXXFLAGS
# RUN sed -i 's/Build openjpeg/&\nexport CFLAGS=${CFLAGS/-O1/-O2}\nexport CXXFLAGS=${CXXFLAGS/-O1/-O2}/' $SRC/build.sh