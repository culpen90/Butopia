# Building Butopia

## Pinned inputs

`locks/sources.env` pins the Butopia and Alpine versions, the annotated Alpine
`aports` release commit, the builder image digest, and `SOURCE_DATE_EPOCH`.
Alpine's `v3.24/main` and `v3.24/community` repositories remain update streams;
the generated `dist/APK-MANIFEST.txt` records the exact package resolution for
each artifact.

## macOS builder

`make builder` creates a Lima VM named `butopia-builder` from
`builder/lima.yaml`. It uses a checksum-pinned Alpine 3.24.1 x86_64 cloud image,
QEMU software translation, two vCPUs, 4 GiB RAM, and a private 30 GiB disk.
The source tree is copied into the VM for each build; no Linux chroot is run on
the macOS filesystem.

The first graphical build downloads roughly a gigabyte of packages. Later builds
reuse the VM's `~/.cache/butopia` source and signing caches.

## Linux or container build

On an Alpine 3.24 x86_64 host with the prerequisites installed:

```sh
./scripts/build-linux.sh
```

The provided container path is also usable wherever Docker or Podman is
available:

```sh
docker build -t butopia-builder -f builder/Containerfile .
docker run --rm \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$PWD:/source:ro" -v "$PWD/dist:/export" \
  butopia-builder
```

## Signing keys

Development builds create and retain
`~/.cache/butopia/keys/butopia.rsa` inside the builder. Only its public key is
copied next to the ISO. To use a protected release key, set
`BUTOPIA_SIGNING_KEY` to an existing RSA private-key path inside the Linux
builder before invoking `scripts/build-linux.sh`.

Never commit a private APK signing key.

## Reproducibility boundary

The profile, aports source, timestamps, and release versions are pinned. A
stable signing key and the emitted APK manifest are also required before two
builds can be expected to match byte-for-byte. Repository security updates can
change package resolution; compare `APK-MANIFEST.txt` before diagnosing an ISO
hash difference.
