#!/usr/bin/env bash

set -euo pipefail

DEST_DIR="${1:-flatpak-build-src/lib/system}"
mkdir -p "${DEST_DIR}"

LIBMPV_PATH="${LIBMPV_PATH:-}"

if [[ -z "${LIBMPV_PATH}" ]]; then
  if command -v ldconfig >/dev/null 2>&1; then
    LIBMPV_PATH="$(ldconfig -p | awk '/libmpv\.so(\.2)?$/{print $NF; exit}')"
  fi
fi

if [[ -z "${LIBMPV_PATH}" ]]; then
  for candidate in \
    /usr/lib/x86_64-linux-gnu/libmpv.so.2 \
    /usr/lib/x86_64-linux-gnu/libmpv.so \
    /usr/lib64/libmpv.so.2 \
    /usr/lib64/libmpv.so
  do
    if [[ -e "${candidate}" ]]; then
      LIBMPV_PATH="${candidate}"
      break
    fi
  done
fi

if [[ -z "${LIBMPV_PATH}" || ! -e "${LIBMPV_PATH}" ]]; then
  echo "Unable to locate libmpv on the build host." >&2
  exit 1
fi

declare -A COPIED_PATHS=()
declare -A COPIED_TARGETS=()

should_skip_library() {
  case "$(basename "$1")" in
    ld-linux-*.so.*|libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libresolv.so.*|libutil.so.*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

copy_library() {
  local source="$1"
  local base
  base="$(basename "${source}")"

  if should_skip_library "${source}"; then
    return 0
  fi

  if [[ -n "${COPIED_PATHS[${source}]:-}" ]]; then
    return 0
  fi
  COPIED_PATHS["${source}"]=1

  if [[ -L "${source}" ]]; then
    local target
    target="$(readlink "${source}")"
    if [[ "${target}" != /* ]]; then
      target="$(dirname "${source}")/${target}"
    fi
    target="$(realpath "${target}")"
    copy_library "${target}"
    ln -sf "$(basename "${target}")" "${DEST_DIR}/${base}"
    return 0
  fi

  install -Dm755 "${source}" "${DEST_DIR}/${base}"

  local real_source
  real_source="$(realpath "${source}")"
  if [[ -n "${COPIED_TARGETS[${real_source}]:-}" ]]; then
    return 0
  fi
  COPIED_TARGETS["${real_source}"]=1

  while IFS= read -r dependency; do
    if [[ "${dependency}" == /* ]]; then
      copy_library "${dependency}"
    fi
  done < <(ldd "${source}" | awk '{for (i = 1; i <= NF; ++i) if ($i ~ /^\//) print $i}')
}

copy_library "${LIBMPV_PATH}"

for alias in libmpv.so libmpv.so.2; do
  if [[ -e "$(dirname "${LIBMPV_PATH}")/${alias}" ]]; then
    copy_library "$(dirname "${LIBMPV_PATH}")/${alias}"
  fi
done

echo "Bundled libmpv closure into ${DEST_DIR}"
