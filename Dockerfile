# OmniDBF - Node + .NET 8 & 9 + Python + Lune
# Supports: Prometheus, LuaObfuscator, MoonSec V3, Hercules, IronBrew 2,
#           77fuscator, Clyde, Ironveil V1, PSU, MoonVeil, Goofyscator,
#           Luraph v15
FROM node:20-bookworm

# Install .NET + python for Hercules + Delta bypass
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl ca-certificates icu-devtools libicu-dev python3 python3-pip unzip \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

# Install Delta bypass Python dependencies (captcha solver + auth client)
RUN pip3 install --no-cache-dir --break-system-packages \
    numpy scipy Pillow requests pycryptodome fake-useragent numba \
    fastapi uvicorn

# Lune runs the environment logger behind /dump. Pinned: the analyzer is written
# against 0.10.5's stdlib (luau.load with injectGlobals=false, in particular) and
# a newer Lune has changed that surface before. aarch64 is handled because
# Railway can schedule either architecture.
ARG LUNE_VERSION=0.10.5
RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
      x86_64)  asset="lune-${LUNE_VERSION}-linux-x86_64.zip" ;; \
      aarch64) asset="lune-${LUNE_VERSION}-linux-aarch64.zip" ;; \
      *) echo "no Lune build for $arch" >&2; exit 1 ;; \
    esac; \
    wget -q "https://github.com/lune-org/lune/releases/download/v${LUNE_VERSION}/${asset}" -O /tmp/lune.zip; \
    unzip -q -o /tmp/lune.zip -d /usr/local/bin; \
    chmod +x /usr/local/bin/lune; \
    rm -f /tmp/lune.zip; \
    lune --version

# Java (JRE headless) for the PSU engine's unluac decompile step
RUN apt-get update && apt-get install -y --no-install-recommends \
    default-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# Install .NET 8 and 9 (8 for 77fuscator, 9 for IronBrew2)
RUN wget -q https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet \
    && /tmp/dotnet-install.sh --channel 9.0 --install-dir /usr/share/dotnet \
    && ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet \
    && dotnet --info

WORKDIR /app

# Prevent dotenvx/vestauth wrapper from overriding Railway env vars
# (no DOTENV_PRIVATE_KEY here on purpose: .env is dockerignored, Railway
# variables are the only source of truth)
ENV DOTENV_CONFIG_OVERRIDE=false

# Install node deps first (cached)
COPY package*.json ./
RUN npm ci --omit=dev || npm install --omit=dev

# Copy rest ( .dockerignore excludes .env on purpose )
COPY . .

# Render/health-check server binds to $PORT (default 3000)
EXPOSE 3000

# Install Ironveil V1 engine dependencies (pure JS, no native builds)
RUN cd deobfuscators/IronveilV1/deobfuscator && npm install --omit=dev

# Install PSU engine dependencies (luaparse, pure JS)
RUN cd deobfuscators/PSU-Deobfuscator && npm install --omit=dev

# The Luraph v15 engine runs the script in a real Luau VM (bin/luau). Ship the
# runtime in the image: the engine's own downloader is a fallback, not something
# to depend on at request time.
RUN set -eux; \
    bin="deobfuscators/luraph_v15/deobf/bin"; \
    mkdir -p "$bin"; \
    wget -q "https://github.com/luau-lang/luau/releases/latest/download/luau-ubuntu.zip" -O /tmp/luau.zip; \
    unzip -q -o /tmp/luau.zip -d /tmp/luau-rel; \
    cp /tmp/luau-rel/luau /tmp/luau-rel/luau-ast "$bin/"; \
    chmod +x "$bin/luau" "$bin/luau-ast"; \
    rm -rf /tmp/luau.zip /tmp/luau-rel; \
    printf 'print("luau-ok")\n' > /tmp/luau_probe.luau; \
    "$bin/luau" /tmp/luau_probe.luau | grep -q luau-ok; \
    printf 'print("luauast-ok")\n' > /tmp/luauast_probe.luau; \
    "$bin/luau-ast" /tmp/luauast_probe.luau > /dev/null; \
    rm -f /tmp/luau_probe.luau /tmp/luauast_probe.luau

# Verify the runtimes and every engine artifact at build time. Render builds
# from git, so an engine that is untracked or ignored is simply absent in the
# image �?" and the symptom is a runtime message that blames the user's script.
# Failing here instead makes that a build error with the path in it.
RUN dotnet --list-runtimes \
 && python3 --version \
 && java -version \
 && node verify_engines.js

# The /dump engine is Luau source that must be cloned, and Lune must be able
# to load it. Prove both here: an absent envlogger/ (untracked, or arriving
# as an empty gitlink) would otherwise only surface as a failed dump at runtime.
RUN test -f envlogger/src/main.luau \
 && printf 'print("ok")\n' > /tmp/dumpprobe.lua \
 && cd envlogger && timeout 60 lune run src/main -- env /tmp/dumpprobe.lua --timeout 10 --out /tmp/dumpprobe.out \
 && grep -q 'fuhed at OmniDBF' /tmp/dumpprobe.out \
 && echo "dump engine starts OK"

# The MoonSec engine is the one that broke in production, so prove the assembly
# actually starts under this .NET rather than only checking that its files exist.
# (Whether the native liblua54.so is intact is checked by verify_engines.js, which
# reads its ELF magic.) A non-zero exit from --help is fine — the engine printing
# usage is a successful start; what must not appear is a load failure. Bounded by
# `timeout` with stdin closed so a prompt cannot hang the build.
RUN timeout 60 dotnet deobfuscators/MoonsecDeobf/bin/Release/net8.0/MoonsecDeobfuscator.dll --help < /dev/null > /tmp/moonsec_probe.txt 2>&1; \
    if grep -qiE "libcoreclr|DllNotFoundException|liblua54|framework.*not found|A fatal error|You must install" /tmp/moonsec_probe.txt; then \
        echo "MoonSec engine cannot start on this image:"; cat /tmp/moonsec_probe.txt; exit 1; \
    else \
        echo "MoonSec engine starts OK"; head -n 5 /tmp/moonsec_probe.txt; \
    fi

CMD ["node", "bot.js"]
