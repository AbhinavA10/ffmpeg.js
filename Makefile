# Compile FFmpeg and all its dependencies to JavaScript.
# You need emsdk environment installed and activated, see:
# <https://kripken.github.io/emscripten-site/docs/getting_started/downloads.html>.

PRE_JS = build/pre.js
POST_JS_SYNC = build/post-sync.js
POST_JS_WORKER = build/post-worker.js

COMMON_FILTERS = aresample scale crop overlay hstack vstack
COMMON_DEMUXERS = matroska ogg mov mp3 wav image2 concat rtsp
COMMON_DECODERS = vp8 h264 vorbis opus mp3 aac pcm_s16le mjpeg png
# need h264 decoder

MP4_MUXERS = mp4 mp3 null mpegts
MP4_ENCODERS = libx264 libmp3lame aac
FFMPEG_MP4_BC = build/ffmpeg-mp4/ffmpeg.bc
FFMPEG_MP4_PC_PATH = ../x264/dist/lib/pkgconfig
MP4_SHARED_DEPS = \
	build/lame/dist/lib/libmp3lame.so \
	build/x264/dist/lib/libx264.so

all: mp4
mp4: ffmpeg-mp4.js ffmpeg-worker-mp4.js

clean: clean-js \
	clean-lame clean-x264 clean-ffmpeg-mp4
clean-js:
	rm -f ffmpeg*.js
clean-lame:
	cd build/lame && git clean -xdf
clean-x264:
	cd build/x264 && git clean -xdf
clean-ffmpeg-mp4:
	cd build/ffmpeg-mp4 && git clean -xdf

build/lame/dist/lib/libmp3lame.so:
	cd build/lame/lame && \
	git reset --hard && \
	patch -p2 < ../../lame-fix-ld.patch && \
	emconfigure ./configure \
		CFLAGS="-DNDEBUG -O3" \
		--prefix="$$(pwd)/../dist" \
		--host=x86-none-linux \
		--disable-static \
		\
		--disable-gtktest \
		--disable-analyzer-hooks \
		--disable-decoder \
		--disable-frontend \
		&& \
	emmake make -j && \
	emmake make install

build/x264/dist/lib/libx264.so:
	cd build/x264 && \
	emconfigure ./configure \
		--prefix="$$(pwd)/dist" \
		--extra-cflags="-Wno-unknown-warning-option" \
		--host=x86-none-linux \
		--disable-cli \
		--enable-shared \
		--disable-opencl \
		--disable-thread \
		--disable-interlaced \
		--bit-depth=8 \
		--chroma-format=420 \
		--disable-asm \
		\
		--disable-avs \
		--disable-swscale \
		--disable-lavf \
		--disable-ffms \
		--disable-gpac \
		--disable-lsmash \
		&& \
	emmake make -j && \
	emmake make install

# TODO(Kagami): Emscripten documentation recommends to always use shared
# libraries but it's not possible in case of ffmpeg because it has
# multiple declarations of `ff_log2_tab` symbol. GCC builds FFmpeg fine
# though because it uses version scripts and so `ff_log2_tag` symbols
# are not exported to the shared libraries. Seems like `emcc` ignores
# them. We need to file bugreport to upstream. See also:
# - <https://kripken.github.io/emscripten-site/docs/compiling/Building-Projects.html>
# - <https://github.com/kripken/emscripten/issues/831>
# - <https://ffmpeg.org/pipermail/libav-user/2013-February/003698.html>
FFMPEG_COMMON_ARGS = \
	--cc=emcc \
	--ranlib=emranlib \
	--enable-cross-compile \
	--target-os=none \
	--arch=x86 \
	--disable-runtime-cpudetect \
	--disable-asm \
	--disable-fast-unaligned \
	--disable-pthreads \
	--disable-w32threads \
	--disable-os2threads \
	--disable-debug \
	--disable-stripping \
	--disable-safe-bitstream-reader \
	\
	--disable-all \
	--enable-ffmpeg \
	--enable-avcodec \
	--enable-avformat \
	--enable-avfilter \
	--enable-swresample \
	--enable-swscale \
	--enable-network \
	--disable-d3d11va \
	--disable-dxva2 \
	--disable-vaapi \
	--disable-vdpau \
	$(addprefix --enable-decoder=,$(COMMON_DECODERS)) \
	$(addprefix --enable-demuxer=,$(COMMON_DEMUXERS)) \
	--enable-protocol=file \
	--enable-protocol=tcp \
	--enable-protocol=udp \
	--enable-protocol=rtp \
	$(addprefix --enable-filter=,$(COMMON_FILTERS)) \
	--disable-bzlib \
	--disable-iconv \
	--disable-libxcb \
	--disable-lzma \
	--disable-sdl2 \
	--disable-securetransport \
	--disable-xlib \
	--enable-zlib

build/ffmpeg-mp4/ffmpeg.bc: $(MP4_SHARED_DEPS)
	cd build/ffmpeg-mp4 && \
	EM_PKG_CONFIG_PATH=$(FFMPEG_MP4_PC_PATH) emconfigure ./configure \
		$(FFMPEG_COMMON_ARGS) \
		$(addprefix --enable-encoder=,$(MP4_ENCODERS)) \
		$(addprefix --enable-muxer=,$(MP4_MUXERS)) \
		--enable-gpl \
		--enable-libmp3lame \
		--enable-libx264 \
		--extra-cflags="-s USE_ZLIB=1 -I../lame/dist/include" \
		--extra-ldflags="-L../lame/dist/lib" \
		&& \
	emmake make -j && \
	cp ffmpeg ffmpeg.bc

EMCC_COMMON_ARGS = \
	-O3 \
	--closure 1 \
	--memory-init-file 0 \
	-s WASM=0 \
	-s WASM_ASYNC_COMPILATION=0 \
	-s ASSERTIONS=0 \
	-s EXIT_RUNTIME=1 \
	-s NODEJS_CATCH_EXIT=0 \
	-s NODEJS_CATCH_REJECTION=0 \
	-s TOTAL_MEMORY=67108864 \
	-lnodefs.js -lworkerfs.js \
	--pre-js $(PRE_JS) \
	-o $@

ffmpeg-mp4.js: $(FFMPEG_MP4_BC) $(PRE_JS) $(POST_JS_SYNC)
	emcc $(FFMPEG_MP4_BC) $(MP4_SHARED_DEPS) \
		--post-js $(POST_JS_SYNC) \
		$(EMCC_COMMON_ARGS) -O2

ffmpeg-worker-mp4.js: $(FFMPEG_MP4_BC) $(PRE_JS) $(POST_JS_WORKER)
	emcc $(FFMPEG_MP4_BC) $(MP4_SHARED_DEPS) \
		--post-js $(POST_JS_WORKER) \
		$(EMCC_COMMON_ARGS) -O2
