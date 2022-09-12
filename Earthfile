VERSION 0.6

# curl -s 'https://registry.hub.docker.com/v2/repositories/hexpm/elixir/tags/' | jq '."results"[]["name"]'

all:
    ARG TAG
    ARG BRANCH
    BUILD +test
    BUILD +get-tag-from-branch --BUILD=+build --TAG=${TAG}
    
build-tag:
    FROM debian:latest
    ARG BUMP  # major, minor, patch, pre, release
    ARG PRE=rc
    ARG VERSION
    ARG INCLUDE_BUILD=""  # date,elixir,erlang,arch,loader,os
    # ^ if empty -> don't include build
    # pull from git -> $(git describe --abbrev=0 --tags 2>/dev/null)
    # defaults
    #   major -> 1
    #   minor -> 0
    #   patch -> 0
    #   pre -> nil
    #   build -> date.elixir.version.erlang.version.arch.loader.version[.os.version]
    #            e.g. 1.0.0-rc.0+20220909T194013Z_x86_64_musl-1.2.3_alpine-3.16.1
    #     -> DateTime.utc_now() |> Map.put(:microsecond, {0, 0}) |> DateTime.to_iso8601() |> String.replace(["-", ":"], "")
    #     -> cat /etc/apk/arch
    #        lscpu | grep Arch | rev | cut -d" " -f1 | rev
    #     -> apk info -w musl 2>/dev/null | grep -Ei 'musl-.* webpage' | cut -d" " -f1 | cut -d- -f2-
    #        apt show libc-bin 2>/dev/null | grep -i version | cut -d" " -f2
    #     -> cat /etc/os-release | grep ID=alpine >/dev/null 2>&1
    #        cat /etc/os-release | grep VERSION_ID= | cut -d= -f2
    #        cat /etc/os-release | grep ID=debian >/dev/null 2>&1
    #        cat /etc/debian_version
    # iex> Version.parse!(app_version)
    
tag:
    FROM debian:latest
    # check if current hash already has a tag
    # GIT_COMMIT=`git rev-parse HEAD`
    # NEEDS_TAG=`git describe --contains $GIT_COMMIT 2>/dev/null`
    # git tag ${TAG}
    # RUN --push git push --tags
    
get-tag-from-branch:
    ARG BUILD
    ARG BRANCH
    ARG TAG
    FROM debian:latest
    IF [ -z "${TAG}" ]
        IF [ "${BRANCH}" == "main" ] || [ "${BRANCH}" == "master" ]
            ARG IMAGE_TAG=latest
        ELSE
            ARG IMAGE_TAG=${BRANCH}
        END
    ELSE
        ARG IMAGE_TAG=${TAG}
    END
    BUILD ${BUILD} --TAG=${IMAGE_TAG}
    
# TODO: vulnerability scan(s) + sbom
test:
    BUILD +check-unused-deps
    BUILD +check-compile-warnings
    BUILD +check-format
    BUILD +lint
    BUILD +lint-docs
    BUILD +test-coverage
    BUILD +audit-deps
    BUILD +audit-web
    BUILD +sec-advisories --ELIXIR_VERSION=${ELIXIR} --ERLANG_VERSION=${ERLANG}
    BUILD +static-analysis --ELIXIR_VERSION=${ELIXIR} --ERLANG_VERSION=${ERLANG}
    BUILD +lint-docker
    
build:
    ARG TAG
    # BUILD +build-glibc --TAG=${TAG}
    BUILD +build-musl --TAG=${TAG}
    
# TODO: fix rel/docker/debian.dockerfile
build-glibc:
    ARG DEBIAN
    ARG TAG
    ARG APP
    ARG APP_VERSION
    FROM +build-image \
        --TARGET=app_build \
        --DOCKERFILE='./rel/docker/debian.dockerfile' \
        --OS_VERSION=${DEBIAN}
    SAVE ARTIFACT _build/${MIX_ENV}/rel/${APP} /release AS LOCAL _build/${MIX_ENV}/rel/glibc/${APP}
    SAVE ARTIFACT _build/${MIX_ENV}/${APP}-${APP_VERSION}.tar.gz /release-tar AS LOCAL _build/${MIX_ENV}/${APP}-${APP_VERSION}-glibc.tar.gz
    BUILD +save-image \
        --TARGET=app \
        --DOCKERFILE='./rel/docker/debian.dockerfile' \
        --OS_VERSION=${DEBIAN} \
        --TAG="${TAG}-debian-${DEBIAN}"
    BUILD +save-image \
        --TARGET=scratch_app \
        --DOCKERFILE='./rel/docker/debian.dockerfile' \
        --OS_VERSION=${DEBIAN} \
        --TAG="${TAG}-glib-scratch"

build-musl:
    ARG ALPINE
    ARG TAG
    ARG APP
    ARG APP_VERSION
    FROM +build-image \
        --DOCKERFILE="./rel/docker/alpine.dockerfile" \
        --TARGET=app_build \
        --OS_VERSION=${ALPINE}
    SAVE ARTIFACT _build/${MIX_ENV}/rel/${APP} /release AS LOCAL _build/${MIX_ENV}/rel/musl/${APP}
    SAVE ARTIFACT _build/${MIX_ENV}/${APP}-${APP_VERSION}.tar.gz /release-tar AS LOCAL _build/${MIX_ENV}/${APP}-${APP_VERSION}-musl.tar.gz
    BUILD +save-image \
        --DOCKERFILE="./rel/docker/alpine.dockerfile" \
        --TARGET=app \
        --OS_VERSION=${ALPINE} \
        --TAG="${TAG}-alpine-${ALPINE}"
    BUILD +save-image \
        --DOCKERFILE="./rel/docker/alpine.dockerfile" \
        --TARGET=scratch_app \
        --OS_VERSION=${ALPINE} \
        --TAG="${TAG}-musl-scratch"

save-image:
    ARG DOCKERFILE
    ARG TARGET
    ARG OS_VERSION
    FROM +build-image \
        --DOCKERFILE=${DOCKERFILE} \
        --TARGET=${TARGET} \
        --OS_VERSION=${OS_VERSION}
    ARG ORG
    ARG IMAGE
    ARG TAG
    SAVE IMAGE --push ${ORG}/${IMAGE}:${TAG}

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

lint-docker:
    FROM hadolint/hadolint:v2.10.0-alpine
    IF [ ${ENABLE_REVIEWDOG} = true ]
        RUN apk --update --upgrade add --no-cache jq && \
            rm -rf /var/cache/apk/*
        DO +SETUP_REVIEWDOG
        COPY scripts/hadolint-to-rdjson.jq rel/docker/.hadolint.yml rel/docker/alpine.dockerfile rel/docker/debian.dockerfile .
        DO +RUN_REVIEWDOG --runners=hadolint
    ELSE
        COPY rel/docker/.hadolint.yml rel/docker/alpine.dockerfile rel/docker/debian.dockerfile .
        RUN hadolint --config .hadolint.yml ./alpine.dockerfile ./debian.dockerfile
    END

static-analysis:
    ARG ERLANG_VERSION
    ARG ELIXIR_VERSION
    FROM +test-base-compiled --ELIXIR=${ELIXIR_VERSION} --ERLANG=${ERLANG_VERSION}
    RUN mkdir -p ./priv/plts
    COPY \
        --build-arg ERLANG_VERSION=${ERLANG_VERSION} \
        --build-arg ELIXIR_VERSION=${ELIXIR_VERSION} \
        +dialyzer-plt/dialyxir_erlang-${ERLANG_VERSION}_elixir-${ELIXIR_VERSION}_deps-${MIX_ENV}.plt.hash \
        +dialyzer-plt/dialyxir_erlang-${ERLANG_VERSION}_elixir-${ELIXIR_VERSION}_deps-${MIX_ENV}.plt \
        +dialyzer-plt/dialyxir_erlang-${ERLANG_VERSION}_elixir-${ELIXIR_VERSION}.plt \
        +dialyzer-plt/dialyxir_erlang-${ERLANG_VERSION}.plt \
        ./priv/plts
    IF [ ${ENABLE_REVIEWDOG} = true ]
        DO +SETUP_REVIEWDOG
        DO +RUN_REVIEWDOG --runners=dialyzer
    ELSE
        RUN mix dialyzer --no-check
    END

dialyzer-plt:
    ARG ERLANG_VERSION
    ARG ELIXIR_VERSION
    FROM +test-base-compiled --ELIXIR=${ELIXIR_VERSION} --ERLANG=${ERLANG_VERSION}
    RUN mkdir -p ./priv
    COPY --if-exists --dir ./priv/plts ./priv
    RUN --no-cache mix dialyzer --plt --force-check
    SAVE ARTIFACT priv/plts/dialyxir_erlang-${ERLANG_VERSION}_elixir-${ELIXIR_VERSION}_deps-${MIX_ENV}.plt.hash AS LOCAL priv/plts/dialyxir_erlang-${ERLANG_VERSION}_elixir-${ELIXIR_VERSION}_deps-${MIX_ENV}.plt.hash
    SAVE ARTIFACT priv/plts/dialyxir_erlang-${ERLANG_VERSION}_elixir-${ELIXIR_VERSION}_deps-${MIX_ENV}.plt AS LOCAL priv/plts/dialyxir_erlang-${ERLANG_VERSION}_elixir-${ELIXIR_VERSION}_deps-${MIX_ENV}.plt
    SAVE ARTIFACT priv/plts/dialyxir_erlang-${ERLANG_VERSION}_elixir-${ELIXIR_VERSION}.plt AS LOCAL priv/plts/dialyxir_erlang-${ERLANG_VERSION}_elixir-${ELIXIR_VERSION}.plt
    SAVE ARTIFACT priv/plts/dialyxir_erlang-${ERLANG_VERSION}.plt AS LOCAL priv/plts/dialyxir_erlang-${ERLANG_VERSION}.plt

sec-advisories:
    ARG ERLANG_VERSION
    ARG ELIXIR_VERSION
    FROM +test-base-compiled --ELIXIR=${ELIXIR_VERSION} --ERLANG=${ERLANG_VERSION}
    ARG ERLANG_PATH=/usr/local/lib/erlang
    ARG ELIXIR_PATH=/usr/local/lib/elixir
    COPY --build-arg ERLANG_VERSION=${ERLANG_VERSION} \
        --build-arg ERLANG_PATH=${ERLANG_PATH} \
        --build-arg ELIXIR_VERSION=${ELIXIR_VERSION} \
        --build-arg ELIXIR_PATH=${ELIXIR_PATH} \
        +pest-cache/cache/${ELIXIR_VERSION}/${ERLANG_VERSION} ./deps/pest/priv/pest.dat
    RUN --no-cache ./deps/pest/pest.erl -V crypto
    RUN ./deps/pest/pest.erl -vb \
        -D ErlangOTP/${ERLANG_VERSION} \
        -D Elixir/${ELIXIR_VERSION}/${ERLANG_VERSION} \
        -p ${ELIXIR_PATH}/lib/elixir/ebin \
        ./_build/${MIX_ENV}/lib || exit 0

pest-cache:
    ARG ERLANG_VERSION
    ARG ELIXIR_VERSION
    FROM +test-base-compiled --ELIXIR=${ELIXIR_VERSION} --ERLANG=${ERLANG_VERSION}
    COPY --if-exists ./priv/pest/pest.dat ./deps/pest/priv/pest.dat
    IF ! ./deps/pest/pest.erl -L | grep "ErlangOTP/${ERLANG_VERSION}" >/dev/null 2>&1
        ARG ERLANG_PATH
        RUN ./deps/pest/pest.erl -vb \
            -d ${ERLANG_PATH}/lib \
            -U pest/dependency/ErlangOTP/${ERLANG_VERSION}
    END
    IF ! ./deps/pest/pest.erl -L | grep "Elixir/${ELIXIR_VERSION}/${ERLANG_VERSION}" >/dev/null 2>&1
        ARG ELIXIR_PATH
        RUN ./deps/pest/pest.erl -vb \
            -p ${ELIXIR_PATH}/lib/elixir/ebin \
            -d ${ELIXIR_PATH}/lib \
            -U pest/dependency/Elixir/${ELIXIR_VERSION}/${ERLANG_VERSION}
    END
    RUN ./deps/pest/pest.erl -U crypto
    SAVE ARTIFACT ./deps/pest/priv/pest.dat /cache/${ELIXIR_VERSION}/${ERLANG_VERSION} AS LOCAL ./priv/pest/pest.dat

# TODO: figure out why it fails with the following the FIRST time only w/ reviewdog...
#       reviewdog: fail to run reviewdog: failed to unmarshal rdjson (DiagnosticResult): proto: syntax error (line 1:1): invalid value Checking
audit-web:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-compiled --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    RUN mix escript.install --force hex sobelow
    IF [ ${ENABLE_REVIEWDOG} = true ]
        RUN apk --update --upgrade add --no-cache jq && \
            rm -rf /var/cache/apk/*
        DO +SETUP_REVIEWDOG
        ENV PATH=${PATH}:${MIX_HOME}/escripts
        COPY scripts/sobelow-to-rdjson.jq .
        DO +RUN_REVIEWDOG --runners=sobelow
    ELSE
        RUN ${MIX_HOME}/escripts/sobelow --exit=Low
    END

audit-deps:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-compiled-deps --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    RUN apk --update --upgrade add --no-cache git; \
        mix escript.install --force hex mix_audit
    RUN ${MIX_HOME}/escripts/mix_audit

# TODO: push to codecov
test-coverage:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-compiled --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    ARG COV_CONFIG=./config/coveralls.json
    RUN mix test --trace --cover --slowest=10

lint-docs:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-compiled --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    COPY --if-exists .doctor.exs .
    RUN mix doctor

lint:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-compiled --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    IF [ ${ENABLE_REVIEWDOG} = true ]
        DO +SETUP_REVIEWDOG
        DO +RUN_REVIEWDOG --runners=credo
    ELSE
        RUN mix credo suggest -a --strict --config-file=./config/.credo.exs
    END

check-compile-warnings:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-compiled-deps --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    COPY --if-exists --dir assets lib test priv ./
    RUN exit 1
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
    RUN mix format --check-formatted

test-base-compiled:
    ARG ELIXIR
    ARG ERLANG
    FROM +check-compile-warnings --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}

test-base-compiled-deps:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base-with-deps --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    RUN mix deps.compile

test-base-with-deps:
    ARG ELIXIR
    ARG ERLANG
    FROM +test-base --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
    COPY --if-exists --dir config ./
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

SETUP_REVIEWDOG:
    COMMAND
    ARG version
    RUN apk add --no-cache curl; \
        curl -sfL https://raw.githubusercontent.com/reviewdog/reviewdog/master/install.sh | sh -s -- -b /usr/local/bin ${version}; \
        apk del --no-network curl
    COPY .reviewdog.yml .
  
RUN_REVIEWDOG:
    COMMAND
    ARG reporter=${REVIEWDOG_REPORTER}
    ARG runners
    ARG options=${REVIEWDOG_OPTIONS}
    ARG github_api_token=${REVIEWDOG_GITHUB_API_TOKEN}
    ENV REVIEWDOG_GITHUB_API_TOKEN=${github_api_token}
    IF [ ${reporter} = local ]
        RUN reviewdog -reporter=${reporter} -runners=${runners} ${options}
    ELSE
        RUN --push reviewdog -reporter=${reporter} -runners=${runners} ${options}
    END
    
# load-otp-env:
#     FROM debian:latest
#     RUN apt-get update -y && \
#         apt-get -y --no-install-recommends install pcregrep
#     COPY --if-exists .env .
#     COPY .tool-versions .
#     IF [ ! -f .env ] || [ ! grep -Ei ERLANG=[0-9.-rc]+ .env >/dev/null 2>&1 ]
#         RUN echo "ERLANG="$(cat .tool-versions | pcregrep -i -o1 'erlang\s+([0-9.]+(-rc[0-9]+)?)') >> .env
#     END
#     IF [ ! grep -Ei ELIXIR=[0-9.-rc]+ .env >/dev/null 2>&1 ]
#         RUN echo "ELIXIR="$(cat .tool-versions | pcregrep -i -o1 'elixir\s+([0-9.]+(-rc[0-9.]+)?)(-otp-[0-9]+)?') >> .env
#     END
#     SAVE ARTIFACT .env AS LOCAL .env
    
# load-app-env:
#     ARG ELIXIR
#     ARG ERLANG
#     FROM +test-base-compiled --ELIXIR=${ELIXIR} --ERLANG=${ERLANG}
#     RUN apk --update --upgrade add --no-cache pcre-tools
#     COPY --if-exists .env .
#     IF [ ! -f .env ] || [ ! grep -Ei APP=.+ .env >/dev/null 2>&1 ]
#         RUN echo "APP="$(mix app.name) >> .env
#     END
#     IF [ ! grep -Ei APP_VERSION=[0-9.-rc]+ .env >/dev/null 2>&1 ]
#         RUN echo "APP_VERSION="$(mix app.version) >> .env
#     END
#     SAVE ARTIFACT .env AS LOCAL .env
