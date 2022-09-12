ARG OS_VERSION

# build erlang otp from source
FROM alpine:${OS_VERSION} AS erlang_build

ARG ERLANG

# install erlang build dependencies
RUN apk --no-cache upgrade
RUN apk add --no-cache \
  dpkg-dev \
  dpkg \
  bash \
  pcre \
  ca-certificates \
  $(if [ "${ERLANG:0:1}" = "1" ]; then echo "libressl-dev"; else echo "openssl-dev"; fi) \
  ncurses-dev \
  unixodbc-dev \
  zlib-dev \
  lksctp-tools-dev \
  autoconf \
  build-base \
  perl-dev \
  wget \
  tar \
  binutils

# pull erlang distribution
RUN mkdir -p /OTP/subdir
RUN wget -nv "https://github.com/erlang/otp/archive/OTP-${ERLANG}.tar.gz" && tar -zxf "OTP-${ERLANG}.tar.gz" -C /OTP/subdir --strip-components=1
WORKDIR /OTP/subdir
RUN ./otp_build autoconf

# see here for more details on configuration environment variables and options
#   - https://www.erlang.org/doc/installation_guide/install#configuring
#   - https://github.com/erlang/otp/blob/master/configure
ARG PIE_LDFLAGS
ARG PIE_CFLAGS
ARG CF_PROTECTION
ARG CC
ARG CFLAGS="-g -O2 -fstack-clash-protection ${CF_PROTECTION} ${PIE_CFLAGS}"
ARG STATIC_CFLAGS
ARG CFLAG_RUNTIME_LIBRARY_PATH
ARG CPP
ARG CPPFLAGS
ARG CXX
ARG CXXFLAGS
ARG LD
ARG LDFLAGS
ARG LIBS
ARG DED_LD
ARG DED_LDFLAGS
ARG DED_LDFLAGS_CONFTEST
ARG DED_LD_FLAG_RUNTIME_LIBRARY_PATH
ARG LFS_CFLAGS
ARG LFS_LDFLAGS
ARG LFS_LIBS
ARG RANLIB
ARG AR
ARG GETCONF

# configure erlang installation
ARG CONFIGURE_OPTS='--without-javac --without-wx --without-debugger --without-observer --without-jinterface --without-cosEvent --without-cosEventDomain --without-cosFileTransfer --without-cosNotification --without-cosProperty --without-cosTime --without-cosTransactions --without-et --without-gs --without-ic --without-megaco --without-orber --without-percept --without-typer --with-ssl --enable-threads --enable-dirty-schedulers --disable-hipe'
RUN ./configure --build="$(dpkg-architecture --query DEB_HOST_GNU_TYPE)" ${CONFIGURE_OPTS}

# install erlang
RUN make -j$(getconf _NPROCESSORS_ONLN)
RUN make install

# install erlang docs
RUN if [ "${ERLANG:0:2}" -ge "23" ]; then make docs DOC_TARGETS=chunks; else true; fi
RUN if [ "${ERLANG:0:2}" -ge "23" ]; then make install-docs DOC_TARGETS=chunks; else true; fi

# cleanup
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN find /usr/local -regex '/usr/local/lib/erlang/\(lib/\|erts-\).*/\(man\|obj\|c_src\|emacs\|info\|examples\)' | xargs rm -rf
RUN find /usr/local -name src | xargs -r find | grep -v '\.hrl$' | xargs rm -v || true
RUN find /usr/local -name src | xargs -r find | xargs rmdir -vp || true
RUN scanelf --nobanner -E ET_EXEC -BF '%F' --recursive /usr/local | xargs -r strip --strip-all
RUN scanelf --nobanner -E ET_DYN -BF '%F' --recursive /usr/local | xargs -r strip --strip-unneeded

#######################################
# minimal erlang distribution
FROM alpine:${OS_VERSION} AS erlang

ARG OS_VERSION
ARG ERLANG
ARG ORG

LABEL ${ORG}.erlang.image.title="erlang-${ERLANG}-alpine-${OS_VERSION}"
LABEL ${ORG}.erlang.image.description="Erlang/OTP Programming Language"
LABEL ${ORG}.erlang.image.licenses="Apache License 2.0"
LABEL ${ORG}.erlang.image.url="https://erlang.org/"
LABEL ${ORG}.erlang.image.vendor="Erlang Ecosystem Foundation"
LABEL ${ORG}.erlang.image.version=${ERLANG}
LABEL ${ORG}.image.keywords="erlang, otp, programming language"
LABEL ${ORG}.image.type="opensource"
LABEL ${ORG}.image.name="erlang"

# install erlang runtime dependencies
RUN apk add --update --no-cache \
  libstdc++ \
  ncurses \
  $(if [ "${ERLANG:0:1}" = "1" ]; then echo "libressl"; else echo "openssl"; fi) \
  unixodbc \
  lksctp-tools

# copy erlang installation from build
COPY --from=erlang_build /usr/local /usr/local

#######################################
# build elixir from source
FROM alpine:${OS_VERSION} AS elixir_build

ARG ELIXIR
ARG ERLANG_MAJOR

# install elixir build dependencies
RUN apk add --no-cache --update \
  wget \
  unzip \
  make

# pull elixir distribution and install
RUN wget -q -O elixir.zip "https://repo.hex.pm/builds/elixir/v${ELIXIR}-otp-${ERLANG_MAJOR}.zip" && unzip -d /ELIXIR elixir.zip
WORKDIR /ELIXIR
RUN make -o compile DESTDIR=/ELIXIR_LOCAL install

#######################################
# minimal elixir distribution
FROM erlang AS elixir

ARG OS_VERSION
ARG ELIXIR
ARG ERLANG
ARG ORG

LABEL ${ORG}.elixir.image.title="elixir-${ELIXIR}-erlang-${ERLANG}-alpine-${OS_VERSION}"
LABEL ${ORG}.elixir.image.description="Elixir is a dynamic, functional language designed for building scalable and maintainable applications"
LABEL ${ORG}.elixir.image.licenses="Apache License 2.0"
LABEL ${ORG}.elixir.image.url="https://elixir-lang.org/"
LABEL ${ORG}.elixir.image.vendor="Dashbit"
LABEL ${ORG}.elixir.image.version=${ELIXIR}
LABEL ${ORG}.image.keywords="elixir, erlang, otp, programming language"
LABEL ${ORG}.image.type="opensource"
LABEL ${ORG}.image.name="elixir"

COPY --from=elixir_build /ELIXIR_LOCAL/usr/local /usr/local

#######################################
# build application
FROM elixir AS app_build

# show versions
RUN erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().'  -noshell
RUN elixir -v

# install application build dependencies
RUN apk --update --upgrade add --no-cache openssl ncurses-libs && \
    rm -rf /var/cache/apk/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only ${MIX_ENV}
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# note: if your project uses a tool like https://purgecss.com/,
# which customizes asset compilation based on what it finds in
# your Elixir templates, you will need to move the asset compilation
# step down so that `lib` is available.

# compile assets
COPY priv priv
COPY assets assets
RUN mix assets.deploy

# compile the release
COPY lib lib
RUN mix compile

# changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

# release
COPY rel rel
RUN mix release

#######################################
# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM alpine:${OS_VERSION} AS app

ARG ORG
ARG OS_VERSION
ARG APP
ARG APP_VERSION

LABEL ${ORG}.app.image.title="${APP}-${APP_VERSION}-apline-${OS_VERSION}"
LABEL ${ORG}.app.image.version=${APP_VERSION}
LABEL ${ORG}.image.keywords="elixir, erlang, otp, programming language"
LABEL ${ORG}.image.type="opensource"
LABEL ${ORG}.image.name=${APP}

# install runtime dependencies
RUN apk --update --upgrade add --no-cache \
    ncurses \
    openssl \
    libstdc++ && \
    rm -rf /var/cache/apk/*

WORKDIR /app
RUN chown nobody:nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=app_build --chown=nobody:nobody /app/_build/${MIX_ENV}/rel/${APP} ./

USER nobody

CMD ["/app/bin/server"]

#######################################
FROM app_build as scratch_build

# install scratch build dependencies
RUN apk --update --upgrade add --no-cache \
    file \
    binutils \
    ncurses \
    openssl \
    libstdc++ && \
    rm -rf /var/cache/apk/*

ARG APP

ENV RELEASE="/app/_build/${MIX_ENV}/rel/${APP}"

# strip symbol information out of any ERTS binaries
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN for fat in $(file _build/*/rel/*/erts-*/bin/*|grep "not stripped"|awk '{print $1}'|cut -d: -f1); do \
        strip $fat &>/dev/null; \
    done && \
    # copy any dynamically linked libaries used by ERTS into release
    for lib in $(ldd _build/*/rel/*/erts-*/bin/* _build/*/rel/*/lib/*/priv/lib/* $(which sh) 2>/dev/null|grep "=>"|awk '{print $3}'|sort|uniq); do \
        mkdir -p $(dirname ${RELEASE}$lib); \
        cp -Lv $lib ${RELEASE}$lib; \
    done && \
    # ensure that the link loader is present
    cp /lib/ld-musl*.so.* ${RELEASE}/lib && \
    cp /lib/libcrypto*.so.* ${RELEASE}/lib && \
    cp /lib/libssl*.so.* ${RELEASE}/lib && \
    # and a shell
    cp /bin/sh ${RELEASE}/bin

#######################################
FROM scratch AS scratch_app

ARG ORG
ARG APP
ARG APP_VERSION

LABEL ${ORG}.app.image.title="${APP}-${APP_VERSION}-scratch"
LABEL ${ORG}.app.image.version=${APP_VERSION}
LABEL ${ORG}.image.keywords="elixir, erlang, otp, programming language"
LABEL ${ORG}.image.type="opensource"
LABEL ${ORG}.image.name=${APP}

ENV TZ=GMT
ENV MIX_ENV="prod"

ARG ERTS_VSN

ENV PROGNAME=erl
ENV EMU=beam
ENV ROOTDIR="/"
ENV BINDIR /erts-${ERTS_VSN}/bin

ENV PHX_SERVER=true
ENV RELEASE_ROOT=""
ENV RELEASE_NAME=${APP}
ENV RELEASE_VSN=${APP_VERSION}
ENV RELEASE_COOKIE="Y5J66Y3E6FFVM566MFNNWEMNT3WORN33FIPWYEJ26ROLNOPWKQSA===="
ENV RELEASE_SYS_CONFIG="${RELEASE_ROOT}/releases/${RELEASE_VSN}/sys"

ENTRYPOINT [\
  "exec", \
  "${BINDIR}/erlexec", \
  "-elixir ansi_enabled true", \
  "-noshell", \
  "-s elixir start_cli", \
  "-mode embedded", \
  "-setcookie \"${RELEASE_COOKIE}\"", \
  "-sname \"${RELEASE_NAME}\"", \
  "-config /releases/${RELEASE_VSN}/sys.config", \
  "-boot /releases/${RELEASE_VSN}/start", \
  "-boot_var RELEASE_LIB /lib", \
  "-args_file /releases/${RELEASE_VSN}/vm.args", \
  "-extra", \
  "--no-halt" \
]

COPY --from=scratch_build /app/_build/${MIX_ENV}/rel/${APP}/ /
