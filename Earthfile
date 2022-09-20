VERSION 0.6

# TODO: figure out "automated" tagging...
# curl -s 'https://registry.hub.docker.com/v2/repositories/hexpm/elixir/tags/' | jq '."results"[]["name"]'

all:
    ARG TAG
    BUILD +test
    BUILD +release --TAG=${TAG}

# TODO: vulnerability scan(s)
test-slow:
    BUILD +test
    BUILD +sec-advisories
    BUILD +static-analysis
    
test:
    BUILD +check-unused-deps
    BUILD +check-compile-warnings
    BUILD +check-format
    BUILD +lint
    BUILD +lint-docs
    BUILD +test-coverage
    BUILD +audit-deps
    BUILD +audit-web
    BUILD +lint-dockerfiles
    BUILD +cyclonedx-sbom
    
release:
    ARG TAG
    BUILD +release-glibc --TAG=${TAG}
    BUILD +release-musl --TAG=${TAG}
    BUILD +release-cent
    
# TODO: complete the centos release
release-cent:
    ARG APP
    ARG APP_VERSION
    ARG CENTOS
    BUILD +save-cent-release \
        --APP=${APP} \
        --APP_VERSION=${APP_VERSION} \
        --DEBIAN=${DEBIAN}
    
save-cent-release:
    ARG APP
    ARG APP_VERSION
    ARG CENTOS
    FROM +build-cent \
        --CENTOS=${CENTOS} \
        --TARGET=centos_app_build
    SAVE ARTIFACT _build/${MIX_ENV}/rel/${APP} /release AS LOCAL _build/${MIX_ENV}/rel/cent/${APP}
    SAVE ARTIFACT _build/${MIX_ENV}/${APP}-${APP_VERSION}.tar.gz /release-tar AS LOCAL _build/${MIX_ENV}/${APP}-${APP_VERSION}-cent.tar.gz

save-cent:
    ARG CENTOS
    ARG TARGET
    FROM +build-cent \
        --CENTOS=${CENTOS} \
        --TARGET=${TARGET}
    ARG ORG
    ARG IMAGE
    ARG TAG
    SAVE IMAGE --push ${ORG}/${IMAGE}:${TAG}
    
# NOTE: not sure about these parameters...I just copied them from the Debian build...
build-cent:
    ARG CENTOS
    ARG TARGET
    FROM +build-image \
        --DOCKERFILE="./rel/docker/centos.dockerfile" \
        --CONTEXT="." \
        --OS_VERSION=${CENTOS} \
        --CFLAGS="-g -O2 -fstack-protector -fstack-clash-protection ${CF_PROTECTION} ${PIE_CFLAGS}" \
        --CPPFLAGS="-D_FORTIFY_SOURCE=2" \
        --LDFLAGS="-Wl,-z,relro,-z,now ${PIE_LDFLAGS}" \
        --CONFIGURE_OPTS='--with-ssl --enable-dirty-schedulers' \
        --TARGET=${TARGET}

release-glibc:
    ARG APP
    ARG APP_VERSION
    ARG ERLANG
    ARG ELIXIR
    ARG DEBIAN
    ARG ORG
    ARG IMAGE
    ARG TAG
    BUILD +save-glibc-release \
        --APP=${APP} \
        --APP_VERSION=${APP_VERSION} \
        --DEBIAN=${DEBIAN}
    BUILD +save-glibc \
        --DEBIAN=${DEBIAN} \
        --TARGET=debian_erlang \
        --ORG=${ORG} \
        --IMAGE=erlang \
        --TAG=${ERLANG}-debian-${DEBIAN}
    BUILD +save-glibc \
        --DEBIAN=${DEBIAN} \
        --TARGET=debian_elixir \
        --ORG=${ORG} \
        --IMAGE=elixir \
        --TAG=${ELIXIR}-erlang-${ERLANG}-debian-${DEBIAN}
    BUILD +save-glibc \
        --DEBIAN=${DEBIAN} \
        --TARGET=debian_app \
        --ORG=${ORG} \
        --IMAGE=${IMAGE} \
        --TAG=${TAG}-debian-${DEBIAN}
    BUILD +save-glibc \
        --DEBIAN=${DEBIAN} \
        --TARGET=debian_scratch_app \
        --ORG=${ORG} \
        --IMAGE=${IMAGE} \
        --TAG=${TAG}-glibc-scratch

save-glibc-release:
    ARG APP
    ARG APP_VERSION
    ARG DEBIAN
    FROM +build-glibc \
        --DEBIAN=${DEBIAN} \
        --TARGET=debian_app_build
    SAVE ARTIFACT _build/${MIX_ENV}/rel/${APP} /release AS LOCAL _build/${MIX_ENV}/rel/glibc/${APP}
    SAVE ARTIFACT _build/${MIX_ENV}/${APP}-${APP_VERSION}.tar.gz /release-tar AS LOCAL _build/${MIX_ENV}/${APP}-${APP_VERSION}-glibc.tar.gz

save-glibc:
    ARG DEBIAN
    ARG TARGET
    FROM +build-glibc \
        --DEBIAN=${DEBIAN} \
        --TARGET=${TARGET}
    ARG ORG
    ARG IMAGE
    ARG TAG
    SAVE IMAGE --push ${ORG}/${IMAGE}:${TAG}

build-glibc:
    ARG DEBIAN
    ARG TARGET
    FROM +build-image \
        --DOCKERFILE="./rel/docker/debian.dockerfile" \
        --CONTEXT="." \
        --OS_VERSION=${DEBIAN} \
        --CFLAGS="-g -O2 -fstack-protector -fstack-clash-protection ${CF_PROTECTION} ${PIE_CFLAGS}" \
        --CPPFLAGS="-D_FORTIFY_SOURCE=2" \
        --LDFLAGS="-Wl,-z,relro,-z,now ${PIE_LDFLAGS}" \
        --CONFIGURE_OPTS='--with-ssl --enable-dirty-schedulers' \
        --TARGET=${TARGET}
       
release-musl:
    ARG APP
    ARG APP_VERSION
    ARG ERLANG
    ARG ELIXIR
    ARG ALPINE
    ARG ORG
    ARG IMAGE
    ARG TAG
    BUILD +save-musl-release \
        --APP=${APP} \
        --APP_VERSION=${APP_VERSION} \
        --ALPINE=${ALPINE}
    BUILD +save-musl \
        --ALPINE=${ALPINE} \
        --TARGET=alpine_erlang \
        --ORG=${ORG} \
        --IMAGE=erlang \
        --TAG=${ERLANG}-alpine-${ALPINE}
    BUILD +save-musl \
        --ALPINE=${ALPINE} \
        --TARGET=alpine_elixir \
        --ORG=${ORG} \
        --IMAGE=elixir \
        --TAG=${ELIXIR}-erlang-${ERLANG}-alpine-${ALPINE}
    BUILD +save-musl \
        --ALPINE=${ALPINE} \
        --TARGET=alpine_app \
        --ORG=${ORG} \
        --IMAGE=${IMAGE} \
        --TAG=${TAG}-alpine-${ALPINE}
    BUILD +save-musl \
        --ALPINE=${ALPINE} \
        --TARGET=alpine_scratch_app \
        --ORG=${ORG} \
        --IMAGE=${IMAGE} \
        --TAG=${TAG}-musl-scratch
    
save-musl-release:
    ARG APP
    ARG APP_VERSION
    ARG ALPINE
    FROM +build-musl \
        --ALPINE=${ALPINE} \
        --TARGET=alpine_app_build
    SAVE ARTIFACT _build/${MIX_ENV}/rel/${APP} /release AS LOCAL _build/${MIX_ENV}/rel/musl/${APP}
    SAVE ARTIFACT _build/${MIX_ENV}/${APP}-${APP_VERSION}.tar.gz /release-tar AS LOCAL _build/${MIX_ENV}/${APP}-${APP_VERSION}-musl.tar.gz

save-musl:
    ARG ALPINE
    ARG TARGET
    FROM +build-musl \
        --ALPINE=${ALPINE} \
        --TARGET=${TARGET}
    ARG ORG
    ARG IMAGE
    ARG TAG
    SAVE IMAGE --push ${ORG}/${IMAGE}:${TAG}

build-musl:
    ARG ALPINE
    ARG TARGET
    FROM +build-image \
        --DOCKERFILE="./rel/docker/alpine.dockerfile" \
        --CONTEXT="." \
        --OS_VERSION=${ALPINE} \
        --CFLAGS="-g -O2 -fstack-clash-protection ${CF_PROTECTION} ${PIE_CFLAGS}" \
        --CONFIGURE_OPTS='--without-javac --without-wx --without-debugger --without-observer --without-jinterface --without-cosEvent --without-cosEventDomain --without-cosFileTransfer --without-cosNotification --without-cosProperty --without-cosTime --without-cosTransactions --without-et --without-gs --without-ic --without-megaco --without-orber --without-percept --without-typer --with-ssl --enable-threads --enable-dirty-schedulers --disable-hipe' \
        --TARGET=${TARGET}

build-image:
    ARG DOCKERFILE="./rel/docker/alpine.dockerfile"
    ARG CONTEXT="."
    ARG TARGET
    ARG OS_VERSION
    ARG APP
    ARG APP_VERSION
    ARG ERLANG
    ARG ELIXIR
    ARG ERLANG_MAJOR
    ARG ERTS_VSN
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
    ARG CONFIGURE_OPTS='--without-javac --without-wx --without-debugger --without-observer --without-jinterface --without-cosEvent --without-cosEventDomain --without-cosFileTransfer --without-cosNotification --without-cosProperty --without-cosTime --without-cosTransactions --without-et --without-gs --without-ic --without-megaco --without-orber --without-percept --without-typer --with-ssl --enable-threads --enable-dirty-schedulers --disable-hipe'
    FROM DOCKERFILE \
        -f ${DOCKERFILE} \
        --target ${TARGET} \
        --build-arg OS_VERSION=${OS_VERSION} \
        --build-arg ELIXIR=${ELIXIR} \
        --build-arg ERLANG=${ERLANG} \
        --build-arg ERLANG_MAJOR=${ERLANG_MAJOR} \
        --build-arg ERTS_VSN=${ERTS_VSN} \
        --build-arg ORG=${ORG} \
        --build-arg APP=${APP} \
        --build-arg APP_VERSION=${APP_VERSION} \
        --build-arg PIE_LDFLAGS=${PIE_LDFLAGS} \
        --build-arg PIE_CFLAGS=${PIE_CFLAGS} \
        --build-arg CF_PROTECTION=${CF_PROTECTION} \
        --build-arg CC=${CC} \
        --build-arg CFLAGS=${CFLAGS} \
        --build-arg STATIC_CFLAGS=${STATIC_CFLAGS} \
        --build-arg CFLAG_RUNTIME_LIBRARY_PATH=${CFLAG_RUNTIME_LIBRARY_PATH} \
        --build-arg CPP=${CPP} \
        --build-arg CPPFLAGS=${CPPFLAGS} \
        --build-arg CXX=${CXX} \
        --build-arg CXXFLAGS=${CXXFLAGS} \
        --build-arg LD=${LD} \
        --build-arg LDFLAGS=${LDFLAGS} \
        --build-arg LIBS=${LIBS} \
        --build-arg DED_LD=${DED_LD} \
        --build-arg DED_LDFLAGS=${DED_LDFLAGS} \
        --build-arg DED_LDFLAGS_CONFTEST=${DED_LDFLAGS_CONFTEST} \
        --build-arg DED_LD_FLAG_RUNTIME_LIBRARY_PATH=${DED_LD_FLAG_RUNTIME_LIBRARY_PATH} \
        --build-arg LFS_CFLAGS=${LFS_CFLAGS} \
        --build-arg LFS_LDFLAGS=${LFS_LDFLAGS} \
        --build-arg LFS_LIBS=${LFS_LIBS} \
        --build-arg RANLIB=${RANLIB} \
        --build-arg AR=${AR} \
        --build-arg GETCONF=${GETCONF} \
        --build-arg CONFIGURE_OPTS=${CONFIGURE_OPTS} \
        ${CONTEXT}

lint-dockerfiles:
    BUILD +lint-dockerfile --DOCKER_FILE=alpine.dockerfile --DOCKER_PATH=rel/docker
    # BUILD +lint-dockerfile --DOCKER_FILE=centos.dockerfile --DOCKER_PATH=rel/docker
    BUILD +lint-dockerfile --DOCKER_FILE=debian.dockerfile --DOCKER_PATH=rel/docker
    BUILD +lint-dockerfile --DOCKER_FILE=dev.dockerfile --DOCKER_PATH=.devcontainer

lint-dockerfile:
    ARG DOCKER_PATH=.
    ARG DOCKER_FILE=Dockerfile
    FROM hadolint/hadolint:v2.10.0-alpine
    COPY rel/docker/.hadolint.yml .
    COPY ${DOCKER_PATH}/${DOCKER_FILE} .
    RUN hadolint --config .hadolint.yml ${DOCKER_FILE}

static-analysis:
    ARG ERLANG
    ARG ELIXIR
    FROM +test-base-compiled --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    COPY ./config/.dialyzer_ignore.exs ./config
    RUN mkdir -p ./priv/plts
    COPY \
        --build-arg ERLANG=${ERLANG} \
        --build-arg ELIXIR=${ELIXIR} \
        +dialyzer-plt/dialyxir_erlang-${ERLANG}_elixir-${ELIXIR}_deps-${MIX_ENV}.plt.hash \
        +dialyzer-plt/dialyxir_erlang-${ERLANG}_elixir-${ELIXIR}_deps-${MIX_ENV}.plt \
        +dialyzer-plt/dialyxir_erlang-${ERLANG}_elixir-${ELIXIR}.plt \
        +dialyzer-plt/dialyxir_erlang-${ERLANG}.plt \
        ./priv/plts
    RUN mix dialyzer --no-check

dialyzer-plt:
    ARG ERLANG
    ARG ELIXIR
    FROM +test-base-compiled --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    RUN mkdir -p ./priv
    COPY --if-exists --dir ./priv/plts ./priv
    RUN --no-cache mix dialyzer --plt --force-check
    SAVE ARTIFACT priv/plts/dialyxir_erlang-${ERLANG}_elixir-${ELIXIR}_deps-${MIX_ENV}.plt.hash AS LOCAL priv/plts/dialyxir_erlang-${ERLANG}_elixir-${ELIXIR}_deps-${MIX_ENV}.plt.hash
    SAVE ARTIFACT priv/plts/dialyxir_erlang-${ERLANG}_elixir-${ELIXIR}_deps-${MIX_ENV}.plt AS LOCAL priv/plts/dialyxir_erlang-${ERLANG}_elixir-${ELIXIR}_deps-${MIX_ENV}.plt
    SAVE ARTIFACT priv/plts/dialyxir_erlang-${ERLANG}_elixir-${ELIXIR}.plt AS LOCAL priv/plts/dialyxir_erlang-${ERLANG}_elixir-${ELIXIR}.plt
    SAVE ARTIFACT priv/plts/dialyxir_erlang-${ERLANG}.plt AS LOCAL priv/plts/dialyxir_erlang-${ERLANG}.plt

sec-advisories:
    ARG ERLANG
    ARG ELIXIR
    FROM +test-base-compiled --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    ARG ERLANG_PATH=/usr/local/lib/erlang
    ARG ELIXIR_PATH=/usr/local/lib/elixir
    COPY --build-arg ERLANG=${ERLANG} \
        --build-arg ERLANG_PATH=${ERLANG_PATH} \
        --build-arg ELIXIR=${ELIXIR} \
        --build-arg ELIXIR_PATH=${ELIXIR_PATH} \
        +pest-cache/cache/${ELIXIR}/${ERLANG} ./deps/pest/priv/pest.dat
    RUN --no-cache ./deps/pest/pest.erl -V crypto
    RUN ./deps/pest/pest.erl -vb \
        -D ErlangOTP/${ERLANG} \
        -D Elixir/${ELIXIR}/${ERLANG} \
        -p ${ELIXIR_PATH}/lib/elixir/ebin \
        ./_build/${MIX_ENV}/lib || exit 0

pest-cache:
    ARG ERLANG
    ARG ELIXIR
    FROM +test-base-compiled --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    COPY --if-exists ./priv/pest/pest.dat ./deps/pest/priv/pest.dat
    IF ! ./deps/pest/pest.erl -L | grep "ErlangOTP/${ERLANG}" >/dev/null 2>&1
        ARG ERLANG_PATH
        RUN ./deps/pest/pest.erl -vb \
            -d ${ERLANG_PATH}/lib \
            -U pest/dependency/ErlangOTP/${ERLANG}
    END
    IF ! ./deps/pest/pest.erl -L | grep "Elixir/${ELIXIR}/${ERLANG}" >/dev/null 2>&1
        ARG ELIXIR_PATH
        RUN ./deps/pest/pest.erl -vb \
            -p ${ELIXIR_PATH}/lib/elixir/ebin \
            -d ${ELIXIR_PATH}/lib \
            -U pest/dependency/Elixir/${ELIXIR}/${ERLANG}
    END
    RUN ./deps/pest/pest.erl -U crypto
    SAVE ARTIFACT ./deps/pest/priv/pest.dat /cache/${ELIXIR}/${ERLANG} AS LOCAL ./priv/pest/pest.dat

cyclonedx-sbom:
    ARG ELIXIR
    ARG ERLANG
    ARG EXPORT_SBOM=false
    FROM +test-base-compiled --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    RUN mix archive.install hex sbom --force
    RUN mix sbom.cyclonedx -o sbom.xml
    IF [ "${EXPORT_SBOM}" == "true" ]
        SAVE ARTIFACT sbom.xml /sbom AS LOCAL sbom.xml
    ELSE
        SAVE ARTIFACT sbom.xml /sbom
    END

audit-web:
    ARG ELIXIR
    ARG ERLANG
    ARG PHOENIX_APP
    FROM +test-base-compiled --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    IF [ "${PHOENIX_APP}" == "true" ]
        RUN mix escript.install --force hex sobelow
        RUN --no-cache ${MIX_HOME}/escripts/sobelow --exit=Low
    END

audit-deps:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-compiled-deps --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    RUN apk --update --upgrade add --no-cache git; \
        mix escript.install --force hex mix_audit
    RUN --no-cache ${MIX_HOME}/escripts/mix_audit

# TODO: push to codecov
test-coverage:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-compiled --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    COPY ./config/coveralls.json ./config
    ARG COV_CONFIG=./config/coveralls.json
    RUN mix test --trace --cover --slowest=10

lint-docs:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-compiled --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    COPY --if-exists .doctor.exs .
    RUN --no-cache mix doctor

lint:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-compiled --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    COPY ./config/.credo.exs ./config
    RUN --no-cache mix credo suggest -a --strict --config-file=./config/.credo.exs

check-compile-warnings:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-with-assets --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    COPY --if-exists --dir lib test ./
    COPY config/runtime.exs config/
    RUN mix compile --warnings-as-errors

check-unused-deps:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    COPY --if-exists --dir config ./
    COPY mix.exs mix.lock .
    RUN cp mix.lock mix.lock.orig && \
        mix deps.get && \
        mix deps.unlock --check-unused && \
        diff -u mix.lock.orig mix.lock && \
        rm mix.lock.orig

check-format:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-with-deps --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    COPY --dir lib test ./
    COPY mix.exs mix.lock .formatter.exs .
    RUN --no-cache mix format --check-formatted

test-base-compiled:
    ARG ELIXIR
    ARG ERLANG
    FROM +check-compile-warnings --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    
test-base-with-assets:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-compiled-deps --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    ARG PHOENIX_APP
    IF [ "${PHOENIX_APP}" == "true" ]
        COPY --if-exists --dir priv assets ./
        RUN mix assets.deploy
    END

test-base-compiled-deps:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-with-deps --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    RUN mkdir config
    COPY --if-exists config/config.exs config/${MIX_ENV}.exs config/
    RUN mix deps.compile

test-base-with-deps:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    COPY mix.exs mix.lock .
    RUN mix deps.get

test-base:
    ARG ELIXIR
    ARG ERLANG
    ARG ALPINE=${ALPINE}
    FROM hexpm/elixir:${ELIXIR}-erlang-${ERLANG}-alpine-${ALPINE}
    ENV ELIXIR_ASSERT_TIMEOUT=10000
    ENV MIX_ENV=test
    ENV MIX_HOME=/root/.mix
    RUN mix do local.hex --force, local.rebar --force
    WORKDIR /app
