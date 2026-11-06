FROM gcr.io/oss-fuzz-base/base-builder:latest@sha256:1f9cf74bc3d7029b528494542f9d9851b256dceed38d3f420989434dc5ae0760
ENV DEBIAN_FRONTEND=noninteractive
ENV SANITIZER=none
RUN apt-get update && apt-get install -y openssh-client nano vim gdb cmake ninja-build tmux lldb htop zlib1g-dev && apt-get clean && rm -rf /var/lib/apt/lists/*
# copy & build LLVM
RUN mkdir $SRC/fsan
WORKDIR $SRC/fsan
COPY llvm-project $SRC/fsan/llvm-project
ENV LLVM="$SRC/fsan/llvm-project/"
WORKDIR $LLVM
RUN git log | head -1 > /src/FSAN.version
RUN rm -rf build build-runtimes || true
RUN mkdir build build-runtimes
ENV FSAN_RT=/src/fsan/runtimes

ENV CXXFLAGS_EXTRA=""
ENV CFLAGS=""
ENV CXXFLAGS=""
ENV CC=""
ENV CXX=""
ENV LDFLAGS=""

WORKDIR $LLVM/build
RUN ls -l /usr/include/zlib.h; find / -name 'libz.*' -not -path '/proc/*' 2>/dev/null; which cmake; env | grep -E 'CMAKE|SYSROOT'; dpkg -l | grep zlib
# Always enable assertions to check everything is good
RUN cmake -DLLVM_ENABLE_PROJECTS="clang;lld" -DLLVM_ENABLE_RUNTIMES="compiler-rt" -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_ASSERTIONS=On -GNinja -DLLVM_PARALLEL_LINK_JOBS=30 -DCLANG_ENABLE_STATIC_ANALYZER=OFF -DCLANG_ENABLE_ARCMT=OFF -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DLLVM_ENABLE_LLD=ON ../llvm/ -DLLVM_FORCE_ENABLE_STATS=ON -DLLVM_TARGETS_TO_BUILD=X86 -DLLVM_TARGETS_TO_BUILD=X86 -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_DOCS=OFF -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON -DCOMPILER_RT_BUILD_XRAY=OFF -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_MEMPROF=OFF -DCOMPILER_RT_BUILD_ORC=OFF -DCOMPILER_RT_BUILD_GWP_ASAN=OFF -DCOMPILER_RT_SANITIZERS_TO_BUILD="hwasan"  -DLLVM_ENABLE_ZLIB=FORCE_ON  && ninja -j120

WORKDIR $LLVM/build-runtimes
RUN cmake -GNinja ../runtimes \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$FSAN_RT \
      -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
      -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
      -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
      -DCMAKE_C_COMPILER=$LLVM/build/bin/clang \
      -DCMAKE_CXX_COMPILER=$LLVM/build/bin/clang++ \
      -DLLVM_USE_LINKER=$LLVM/build/bin/ld.lld \
      -DLLVM_ENABLE_ASSERTIONS=On \
      -DCMAKE_C_FLAGS="-mllvm -rewrite-ptr-subs=1" \
      -DCMAKE_CXX_FLAGS="-mllvm -rewrite-ptr-subs=1" \
      -DLLVM_ENABLE_ZLIB=FORCE_ON  \
 && ninja -j120 && ninja install

# SET ENV FOR FUZZING
ENV LLVM_BUILD="$LLVM/build"
ENV LLVM_BIN="$LLVM_BUILD/bin"
ENV LLVM_LIB="$LLVM_BUILD/lib/x86_64-unknown-linux-gnu"
ENV LLVM_AS="$LLVM_BIN/llvm-as"
ENV LLVM_AR="$LLVM_BIN/llvm-ar"
ENV LLVM_RANLIB="$LLVM_BIN/llvm-ranlib"

# AFL - clone pinned version
ENV AFL="$SRC/aflplusplus"
RUN rm -rf $AFL || true
# RUN git clone https://github.com/ubersandro/AFLplusplus.git $AFL
# TODO: pin version
COPY fsan-afl $AFL
WORKDIR $AFL

# APPLY PATCH FOR FSAN LTO
RUN sed -i 's/\- \-flto=full/\- \-flto\=full \-\-ld-path=\/src\/fsan\/llvm\-project\/build\/bin\/ld.lld/g' $AFL/GNUmakefile.llvm
RUN sed -i 's/\- \-flto=thin/\- \-flto\=thin \-\-ld-path=\/src\/fsan\/llvm\-project\/build\/bin\/ld.lld/g' $AFL/GNUmakefile.llvm
RUN sed -i 's/\- \-flto/\- \-flto \-\-ld-path=\/src\/fsan\/llvm\-project\/build\/bin\/ld.lld/g' $AFL/GNUmakefile.llvm

# NOTE: this is going to build AFL with regular LLVM (minus some changes we can't tweak in the current implementation of FSan because we touch the anlyses in LLVM. Performance toll should be limited though.)
RUN LLVM_CONFIG=$LLVM_BIN/llvm-config make -j12 CC=$LLVM_BIN/clang CXX=$LLVM_BIN/clang++ LDFLAGS="--ld-path=/src/fsan/llvm-project/build/bin/ld.lld" AR=$LLVM_BIN/llvm-ar AS=$LLVM_BIN/llvm-as RANLIB=$LLVM_BIN/llvm-ranlib

ENV CC="$AFL/afl-clang-fast"
ENV CXX="$AFL/afl-clang-fast++"

# COMPILER FLAGS
ENV COMMON_COMP_FLAGS="-O2 -g3 -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -pthread -fno-common -fno-data-sections -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -L/src/fsan/runtimes/lib/ -fno-discard-value-names"
ENV FSAN_CONFIG_COMPILE_FLAGS="-fsanitize=hwaddress,fsan-heap  -mllvm -disable-loop-idiom-all -mllvm -vectorize-slp=0 -mllvm -vectorize-loops=0 -mllvm -fsan-blocklist-tag-filepath=/src/fsan.blocklist -mllvm -fsan-list-of-vars-to-blocklist=/src/fsan.blocklist.vars -mllvm -rewrite-ptr-subs=1 -mllvm -enable-tail-merge=0 -mllvm -hwasan-recover=1"
# FSan runs in the middle by default (same pos. as HWASan)
# ENV CXXFLAGS="$COMMON_COMP_FLAGS -stdlib=libc++ -nostdinc++ -isystem /src/fsan/llvm-project/build/include/c++/v1 $FSAN_CONFIG_COMPILE_FLAGS"
# FIX for dumbass builders: add LDFLAGS here so assimp builds
ENV CXXFLAGS="$COMMON_COMP_FLAGS -stdlib=libc++ -nostdinc++ -isystem $FSAN_RT/include/c++/v1 $FSAN_CONFIG_COMPILE_FLAGS --rtlib=compiler-rt --unwindlib=libunwind -Wno-unused-command-line-argument"
# RUN ln -sf /src/fsan/llvm-project/build/bin/ld.lld /usr/bin/ld # extreme but maybe 
ENV CFLAGS="$COMMON_COMP_FLAGS $FSAN_CONFIG_COMPILE_FLAGS"

# LINKER FLAGS
ENV LD="$LLVM/build/bin/ld.lld"
# ENV LDFLAGS="-fsanitize=hwaddress --ld-path=/src/fsan/llvm-project/build/bin/ld.lld -L/src/fsan/llvm-project/build/lib -stdlib=libc++ --unwindlib=libunwind --rtlib=compiler-rt -Wl,-rpath=/src/fsan/llvm-project/build/lib"

ENV LDFLAGS="-fsanitize=hwaddress --ld-path=$LLVM/build/bin/ld.lld \
  -stdlib=libc++ --unwindlib=libunwind --rtlib=compiler-rt \
  -L$FSAN_RT/lib -Wl,-rpath,$FSAN_RT/lib \
  -L$LLVM/build/lib -Wl,-rpath,$LLVM/build/lib -fuse-ld=/src/fsan/llvm-project/build/bin/ld.lld"
  
ENV CXXFLAGS_EXTRA=""
ENV CCACHE_DISABLE=1
RUN rm -rf `which ccache` || true

ENV HWASAN_SYMBOLIZER_PATH="/usr/local/bin/llvm-symbolizer"
ENV ASAN_SYMBOLIZER_PATH="/usr/local/bin/llvm-symbolizer"
# suitable for fuzzing
ENV HWASAN_OPTIONS="symbolize=0:exitcode=99:halt_on_error=0:recover_report=summary:verbosity=0:detect_leaks=0:allocator_may_return_null=1"

RUN touch /src/fsan.blocklist
RUN touch /src/fsan.blocklist.vars

RUN cp $AFL/utils/aflpp_driver/libAFLDriver.a /usr/lib/libFuzzingEngine.a
RUN cp $AFL/utils/aflpp_driver/libAFLDriver.a /usr/lib/libFuzzingEngine.a
RUN ar -t /usr/lib/libFuzzingEngine.a

# copy relevant scripts to 
# start fuzzing getting corpora from upstream oss-fuzz when available. When not available, repurpose local ones.
COPY oss-fuzz/start-campaign.sh $SRC/fuzz.sh
COPY oss-fuzz/output.py $SRC/output.py
COPY oss-fuzz/quick-check.sh $SRC/quick-check.sh
COPY oss-fuzz/schedule-fuzzer.sh $SRC/schedule-fuzzer.sh
COPY oss-fuzz/results.sh $SRC/results.sh
COPY oss-fuzz/collect-fuzzer-output.sh $SRC/collect-fuzzer-output.sh
COPY oss-fuzz/post-processing.sh $SRC/post-processing.sh
COPY oss-fuzz/collect-other.sh $SRC/collect-other.sh
RUN chmod +x $SRC/*.sh $SRC/*.py
WORKDIR $SRC

RUN echo "alias rebuildllvm='cd /src/fsan/llvm-project/build && ninja && cd -'" >> ~/.bashrc
RUN echo 'alias fuzzercheck="for d in \$(find /out/ -name \"*_0\"); do /src/aflplusplus/afl-whatsup \$d ; done | grep -E \"instance|Crashes\""' >> ~/.bashrc
RUN echo "alias symenable='export HWASAN_OPTIONS=verbosity=0:symbolize=1:halt_on_error=0:abort_on_error=0:detect_leaks=0:recover_report=summary:allocator_may_return_null=1'" >> ~/.bashrc
RUN echo "alias symdebug='export HWASAN_OPTIONS=verbosity=0:symbolize=1:halt_on_error=0:abort_on_error=0:detect_leaks=0:recover_report=verbose:allocator_may_return_null=1'" >> ~/.bashrc
RUN echo "alias symdisable='export HWASAN_OPTIONS=verbosity=0:symbolize=0:halt_on_error=0:abort_on_error=0:detect_leaks=0:recover_report=verbose:allocator_may_return_null=1'" >> ~/.bashrc
RUN echo "alias results='/src/post-processing.sh | grep FUZZER | cut -f2,6 -d\" \" > /fuzzing-campaign/results.txt'" >> ~/.bashrc
RUN echo "alias genoutput='while read l; do echo "INPUT: $l"; $l 2>&1 ; done < /fuzzing-campaign/results.txt  > /fuzzing-campaign/results_output.txt'" >> ~/.bashrc

RUN git config --global --add safe.directory /fuzzing-campaign
RUN echo "set -g mouse on" >> ~/.tmux.conf
COPY oss-fuzz/codeql /src/codeql-queries
RUN echo "alias CHKLIBS='for f in /out/*; do [ -x "$f" ] && ldd "$f" 2>/dev/null | grep -qE 'libc\+\+' && ! ldd "$f" | grep -q "$FSAN_RT/lib/libc++" && echo "WRONG LIBC++: $f"; done'" >> ~/.bashrc

ENV TMUX_TMPDIR=/run/tmux
RUN mkdir -p /run/tmux && chmod 700 /run/tmux