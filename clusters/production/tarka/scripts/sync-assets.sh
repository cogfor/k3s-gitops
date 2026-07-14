#!/bin/sh
set -eu

umask 0027

asset_ref="${ASSET_REPOSITORY}:${ASSET_TAG}"
download=/tmp/tarka-assets-download
releases="${ASSET_ROOT}/releases"

mkdir -p "${HOME}" "${ASSET_ROOT}" "${releases}"

exec 9>"${ASSET_ROOT}/.sync.lock"
flock 9

digest="$(oras resolve "${asset_ref}")"
release="${digest#sha256:}"
destination="${releases}/${release}"

publish_archive() {
  rm -f "${ASSET_ROOT}/archive.next"
  ln -s "releases/${release}/archive" "${ASSET_ROOT}/archive.next"
  mv -fT "${ASSET_ROOT}/archive.next" "${ASSET_ROOT}/archive"
}

prune_releases() {
  for installed in "${releases}"/* "${releases}"/.staging-*; do
    [ -e "${installed}" ] || continue
    [ "${installed}" = "${destination}" ] || rm -rf "${installed}"
  done
}

if [ -f "${destination}/.complete" ]; then
  publish_archive
  prune_releases
  echo "Shared assets ${release} are already present."
  exit 0
fi

staging="${releases}/.staging-${release}"
rm -rf "${download}" "${staging}"
mkdir -p "${download}" "${staging}"

oras pull "${asset_ref}@${digest}" --output "${download}"
archive="${download}/shared-assets.tar.gz"
test -f "${archive}"

tar -tzf "${archive}" | while IFS= read -r path; do
  case "${path}" in
    /*|..|../*|*/..|*/../*|.|./*|*/.|*/./*)
      echo "Unsafe path in shared asset archive: ${path}" >&2
      exit 1
      ;;
    media|media/|media/*|archive|archive/|archive/*) ;;
    *)
      echo "Unexpected path in shared asset archive: ${path}" >&2
      exit 1
      ;;
  esac
done

tar -tvzf "${archive}" | while IFS= read -r entry; do
  case "${entry}" in
    d*|-*) ;;
    *)
      echo "Shared asset archive contains a non-regular entry: ${entry}" >&2
      exit 1
      ;;
  esac
done

tar -xzf "${archive}" -C "${staging}"
test -d "${staging}/media"
test -d "${staging}/archive"

mkdir -p "${ASSET_ROOT}/media"
cp -a "${staging}/media/." "${ASSET_ROOT}/media/"
rm -rf "${staging}/media"
touch "${staging}/.complete"
mv "${staging}" "${destination}"
publish_archive
prune_releases
rm -rf "${download}"

echo "Published shared assets ${release}."
