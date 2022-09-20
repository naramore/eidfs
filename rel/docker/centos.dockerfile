ARG OS_VERSION

# build erlang otp from source
FROM centos:${OS_VERSION} AS centos_erlang_build

ARG ERLANG
ENV OS_MAJOR="$(cat /etc/issue | grep 'Debian GNU/Linux ' | cut -d' ' -f3)"

# install erlang build dependencies
RUN yum update -y
RUN yum install -y \
  autoconf \
  gcc \
  make \
  ncurses-devel \
  unixodbc-devel \
  openssl-devel \
  lksctp-tools-devel \
  wget \
  ca-certificates \
  zlib-devel \
  tar \
  perl-devel \
  pcre
RUN yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm \
  && yum install -y pax-utils

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
ARG CFLAGS="-g -O2 -fstack-protector -fstack-clash-protection ${CF_PROTECTION} ${PIE_CFLAGS}"
ARG STATIC_CFLAGS
ARG CFLAG_RUNTIME_LIBRARY_PATH
ARG CPP
ARG CPPFLAGS="-D_FORTIFY_SOURCE=2"
ARG CXX
ARG CXXFLAGS
ARG LD
ARG LDFLAGS="-Wl,-z,relro,-z,now ${PIE_LDFLAGS}"
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
ARG CONFIGURE_OPTS='--with-ssl --enable-dirty-schedulers'
RUN ./configure ${CONFIGURE_OPTS}

# install erlang
RUN make -j$(getconf _NPROCESSORS_ONLN)
RUN make install

# install erlang docs
RUN bash -c 'if [ "${ERLANG:0:2}" -ge "23" ]; then make docs DOC_TARGETS=chunks; else true; fi'
RUN bash -c 'if [ "${ERLANG:0:2}" -ge "23" ]; then make install-docs DOC_TARGETS=chunks; else true; fi'

# cleanup
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN find /usr/local -regex '/usr/local/lib/erlang/\(lib/\|erts-\).*/\(man\|obj\|c_src\|emacs\|info\|examples\)' | xargs rm -rf
RUN find /usr/local -name src | xargs -r find | grep -v '\.hrl$' | xargs rm -v || true
RUN find /usr/local -name src | xargs -r find | xargs rmdir -vp || true
RUN scanelf --nobanner -E ET_EXEC -BF '%F' --recursive /usr/local | xargs -r strip --strip-all
RUN scanelf --nobanner -E ET_DYN -BF '%F' --recursive /usr/local | xargs -r strip --strip-unneeded

#######################################
# minimal erlang distribution
FROM centos:${OS_VERSION} AS centos_erlang

# install erlang runtime dependencies
RUN yum update -y \
  && yum install -y \
    unixodbc \
    openssl \
    lksctp-tools

# copy erlang installation from build
COPY --from=centos_erlang_build /usr/local /usr/local
ENV LANG=C.UTF-8

#######################################
# build elixir from source
FROM centos:${OS_VERSION} AS centos_elixir_build

# install elixir build dependencies
RUN yum update -y \
  && yum install -y \
    wget \
    ca-certificates \
    unzip \
    make

ARG ELIXIR
ARG ERLANG_MAJOR

# pull elixir distribution and install
RUN wget -q -O elixir.zip "https://repo.hex.pm/builds/elixir/v${ELIXIR}-otp-${ERLANG_MAJOR}.zip" && unzip -d /ELIXIR elixir.zip
WORKDIR /ELIXIR
RUN make -o compile DESTDIR=/ELIXIR_LOCAL install

#######################################
# minimal elixir distribution
FROM centos_erlang AS centos_elixir

COPY --from=centos_elixir_build /ELIXIR_LOCAL/usr/local /usr/local

#######################################
# build application
FROM centos_elixir AS centos_app_build

# show versions
RUN erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().'  -noshell
RUN elixir -v

# install build dependencies
RUN yum update -y \
  && yum install -y git \
  && yum groupinstall -y "development tools"

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
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
