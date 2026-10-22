# uni-api musl build

This repository holds **only a GitHub Actions workflow** — no source code.

The workflow builds the [uni-api](https://github.com/yym68686/uni-api) core
(`uni-api-front`) as a statically linked **musl** binary for `x86_64` Linux,
then publishes it to this repository's Releases.

Source is checked out directly from upstream `yym68686/uni-api` at its
**latest release tag**, so the version number always matches the code.

## Download (stable URL, always latest)

```bash
curl -L -o uni-api-front \
  https://github.com/clerzg/uni-api/releases/latest/download/uni-api-linux-x86_64-musl
chmod +x uni-api-front
```

Checksum:

```bash
curl -L -O https://github.com/clerzg/uni-api/releases/latest/download/uni-api-linux-x86_64-musl.sha256
sha256sum -c uni-api-linux-x86_64-musl.sha256
```

## Run

Place an `api.yaml` next to the binary, then execute it. It listens on `:8000`.

```bash
./uni-api-front
```

Runs on any x86_64 Linux (Alpine, Debian, Ubuntu) — no shared library
dependencies. Measured RSS: ~5 MB.

## Build

Actions → **Build uni-api musl binary (amd64)** → *Run workflow*.
