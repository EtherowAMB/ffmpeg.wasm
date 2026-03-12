# syntax=docker/dockerfile-upstream:master-labs

FROM emscripten/emsdk:3.1.40 AS emsdk-base
ARG EXTRA_CFLAGS
ARG EXTRA_LDFLAGS
ARG FFMPEG_ST
ARG FFMPEG_MT
ENV INSTALL_DIR=/opt
ENV FFMPEG_VERSION=n5.1.4
ENV CFLAGS="-I$INSTALL_DIR/include $CFLAGS $EXTRA_CFLAGS"
ENV CXXFLAGS="$CFLAGS"
ENV LDFLAGS="-L$INSTALL_DIR/lib $LDFLAGS $CFLAGS $EXTRA_LDFLAGS"
ENV EM_PKG_CONFIG_PATH=$EM_PKG_CONFIG_PATH:$INSTALL_DIR/lib/pkgconfig:/emsdk/upstream/emscripten/system/lib/pkgconfig
ENV EM_TOOLCHAIN_FILE=$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake
ENV PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$EM_PKG_CONFIG_PATH
ENV FFMPEG_ST=$FFMPEG_ST
ENV FFMPEG_MT=$FFMPEG_MT
RUN apt-get update && \
      apt-get install -y pkg-config autoconf automake libtool ragel

# 只保留你需要的 x264 编码器
FROM emsdk-base AS x264-builder
ENV X264_BRANCH=4-cores
ADD https://github.com/ffmpegwasm/x264.git#$X264_BRANCH /src
COPY build/x264.sh /src/build.sh
RUN bash -x /src/build.sh

FROM emsdk-base AS ffmpeg-base
RUN embuilder build sdl2 sdl2-mt
ADD https://github.com/FFmpeg/FFmpeg.git#$FFMPEG_VERSION /src
COPY --from=x264-builder $INSTALL_DIR $INSTALL_DIR

# 精简 FFMPEG 构建参数
FROM ffmpeg-base AS ffmpeg-builder
COPY build/ffmpeg.sh /src/build.sh
RUN bash -x /src/build.sh \
      --disable-everything \
      --enable-gpl \
      --enable-libx264 \
      --enable-protocol=file \
      --enable-encoder=libx264 \
      --enable-encoder=aac \
      --enable-decoder=h264 \
      --enable-decoder=hevc \
      --enable-decoder=av1 \
      --enable-decoder=aac \
      --enable-parser=h264 \
      --enable-parser=hevc \
      --enable-parser=av1 \
      --enable-parser=aac \
      --enable-demuxer=mov \
      --enable-demuxer=mp4 \
      --enable-demuxer=aac \
      --enable-muxer=mp4 \
      --enable-filter=crop \
      --enable-filter=hstack \
      --enable-filter=scale \
      --enable-bsf=aac_adtstoasc \
      --enable-swscale \
      --enable-avfilter \
      --enable-avformat \
      --enable-avcodec

# 链接及输出
FROM ffmpeg-builder AS ffmpeg-wasm-builder
COPY src/bind /src/src/bind
COPY src/fftools /src/src/fftools
COPY build/ffmpeg-wasm.sh build.sh
ENV FFMPEG_LIBS="-lx264"
RUN mkdir -p /src/dist/umd && bash -x /src/build.sh \
      ${FFMPEG_LIBS} \
      -o dist/umd/ffmpeg-core.js
RUN mkdir -p /src/dist/esm && bash -x /src/build.sh \
      ${FFMPEG_LIBS} \
      -sEXPORT_ES6 \
      -o dist/esm/ffmpeg-core.js

FROM scratch AS exportor
COPY --from=ffmpeg-wasm-builder /src/dist /dist
