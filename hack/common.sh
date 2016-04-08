#!/bin/bash

# This script provides common script functions for the hacks
# Requires ONION_ROOT to be set

set -o errexit
set -o nounset
set -o pipefail

# The root of the build/dist directory
ONION_ROOT=$(
  unset CDPATH
  onion_root=$(dirname "${BASH_SOURCE}")/..
  cd "${onion_root}"
  pwd
)

ONION_OUTPUT_SUBPATH="${ONION_OUTPUT_SUBPATH:-_output/local}"
ONION_OUTPUT="${ONION_ROOT}/${ONION_OUTPUT_SUBPATH}"
ONION_OUTPUT_BINPATH="${ONION_OUTPUT}/bin"
ONION_LOCAL_BINPATH="${ONION_OUTPUT}/go/bin"
ONION_LOCAL_RELEASEPATH="${ONION_OUTPUT}/releases"

readonly ONION_GO_PACKAGE=github.com/mdshuai/onion
readonly ONION_GOPATH="${ONION_OUTPUT}/go"

readonly ONION_CROSS_COMPILE_PLATFORMS=(
  linux/amd64
  darwin/amd64
  windows/amd64
  linux/386
)
readonly ONION_CROSS_COMPILE_TARGETS=(
  cmd/onion
)
readonly ONION_CROSS_COMPILE_BINARIES=("${ONION_CROSS_COMPILE_TARGETS[@]##*/}")

readonly ONION_ALL_TARGETS=(
  "${ONION_CROSS_COMPILE_TARGETS[@]}"
)

readonly ONION_BINARY_SYMLINKS=(
  onion
)
readonly ONION_BINARY_COPY=(
  onion
)
readonly ONION_BINARY_RELEASE_WINDOWS=(
  onion.exe
)

# onion::binaries_from_targets take a list of build targets and return the
# full go package to be built
onion::binaries_from_targets() {
  local target
  for target; do
    echo "${ONION_GO_PACKAGE}/${target}"
  done
}

# Asks golang what it thinks the host platform is.  The go tool chain does some
# slightly different things when the target platform matches the host platform.
onion::host_platform() {
  echo "$(go env GOHOSTOS)/$(go env GOHOSTARCH)"
}


# Build binaries targets specified
#
# Input:
#   $@ - targets and go flags.  If no targets are set then all binaries targets
#     are built.
#   ONION_BUILD_PLATFORMS - Incoming variable of targets to build for.  If unset
#     then just the host architecture is built.
onion::build_binaries() {
  # Create a sub-shell so that we don't pollute the outer environment
  (
    # Check for `go` binary and set ${GOPATH}.
    onion::setup_env

    # Fetch the version.
    local version_ldflags
    version_ldflags=$(onion::ldflags)

    onion::export_targets "$@"

    local platform
    for platform in "${platforms[@]}"; do
      onion::set_platform_envs "${platform}"
      echo "++ Building go targets for ${platform}:" "${targets[@]}"
      go install "${goflags[@]:+${goflags[@]}}" \
          -ldflags "${version_ldflags}" \
          "${binaries[@]}"
      onion::unset_platform_envs "${platform}"
    done
  )
}

# Generates the set of target packages, binaries, and platforms to build for.
# Accepts binaries via $@, and platforms via ONION_BUILD_PLATFORMS, or defaults to
# the current platform.
onion::export_targets() {
  # Use eval to preserve embedded quoted strings.
  local goflags
  eval "goflags=(${ONION_GOFLAGS:-})"

  targets=()
  local arg
  for arg; do
    if [[ "${arg}" == -* ]]; then
      # Assume arguments starting with a dash are flags to pass to go.
      goflags+=("${arg}")
    else
      targets+=("${arg}")
    fi
  done

  if [[ ${#targets[@]} -eq 0 ]]; then
    targets=("${ONION_ALL_TARGETS[@]}")
  fi

  binaries=($(onion::binaries_from_targets "${targets[@]}"))

  platforms=("${ONION_BUILD_PLATFORMS[@]:+${ONION_BUILD_PLATFORMS[@]}}")
  if [[ ${#platforms[@]} -eq 0 ]]; then
    platforms=("$(onion::host_platform)")
  fi
}


# Takes the platform name ($1) and sets the appropriate golang env variables
# for that platform.
onion::set_platform_envs() {
  [[ -n ${1-} ]] || {
    echo "!!! Internal error.  No platform set in onion::set_platform_envs"
    exit 1
  }

  export GOOS=${platform%/*}
  export GOARCH=${platform##*/}
}

# Takes the platform name ($1) and resets the appropriate golang env variables
# for that platform.
onion::unset_platform_envs() {
  unset GOOS
  unset GOARCH
}


# Create the GOPATH tree under $ONION_ROOT
onion::create_gopath_tree() {
  local go_pkg_dir="${ONION_GOPATH}/src/${ONION_GO_PACKAGE}"
  local go_pkg_basedir=$(dirname "${go_pkg_dir}")

  mkdir -p "${go_pkg_basedir}"
  rm -f "${go_pkg_dir}"

  # TODO: This symlink should be relative.
  ln -s "${ONION_ROOT}" "${go_pkg_dir}"
}


# onion::setup_env will check that the `go` commands is available in
# ${PATH}. If not running on Travis, it will also check that the Go version is
# good enough for the Kubernetes build.
#
# Input Vars:
#   ONION_EXTRA_GOPATH - If set, this is included in created GOPATH
#   ONION_NO_GODEPS - If set, we don't add 'Godeps/_workspace' to GOPATH
#
# Output Vars:
#   export GOPATH - A modified GOPATH to our created tree along with extra
#     stuff.
#   export GOBIN - This is actively unset if already set as we want binaries
#     placed in a predictable place.
onion::setup_env() {
  onion::create_gopath_tree

  if [[ -z "$(which go)" ]]; then
    cat <<EOF

Can't find 'go' in PATH, please fix and retry.
See http://golang.org/doc/install for installation instructions.

EOF
    exit 2
  fi

  # Travis continuous build uses a head go release that doesn't report
  # a version number, so we skip this check on Travis.  It's unnecessary
  # there anyway.
  if [[ "${TRAVIS:-}" != "true" ]]; then
    local go_version
    go_version=($(go version))
    if [[ "${go_version[2]}" < "go1.4" ]]; then
      cat <<EOF

Detected go version: ${go_version[*]}.
S2I requires go version 1.4 or greater.
Please install Go version 1.4 or later.

EOF
      exit 2
    fi
  fi

  GOPATH=${ONION_GOPATH}

  # Append ONION_EXTRA_GOPATH to the GOPATH if it is defined.
  if [[ -n ${ONION_EXTRA_GOPATH:-} ]]; then
    GOPATH="${GOPATH}:${ONION_EXTRA_GOPATH}"
  fi

  # Append the tree maintained by `godep` to the GOPATH unless ONION_NO_GODEPS
  # is defined.
  if [[ -z ${ONION_NO_GODEPS:-} ]]; then
    GOPATH="${GOPATH}:${ONION_ROOT}/Godeps/_workspace"
  fi
  export GOPATH

  # Unset GOBIN in case it already exists in the current session.
  unset GOBIN
}

# This will take binaries from $GOPATH/bin and copy them to the appropriate
# place in ${ONION_OUTPUT_BINDIR}
#
# If ONION_RELEASE_ARCHIVE is set to a directory, it will have tar archives of
# each ONION_RELEASE_PLATFORMS created
#
# Ideally this wouldn't be necessary and we could just set GOBIN to
# ONION_OUTPUT_BINDIR but that won't work in the face of cross compilation.  'go
# install' will place binaries that match the host platform directly in $GOBIN
# while placing cross compiled binaries into `platform_arch` subdirs.  This
# complicates pretty much everything else we do around packaging and such.
onion::place_bins() {
  (
    local host_platform
    host_platform=$(onion::host_platform)

    echo "++ Placing binaries"

    if [[ "${ONION_RELEASE_ARCHIVE-}" != "" ]]; then
      onion::get_version_vars
      mkdir -p "${ONION_LOCAL_RELEASEPATH}"
    fi

    onion::export_targets "$@"

    for platform in "${platforms[@]}"; do
      # The substitution on platform_src below will replace all slashes with
      # underscores.  It'll transform darwin/amd64 -> darwin_amd64.
      local platform_src="/${platform//\//_}"
      if [[ $platform == $host_platform ]]; then
        platform_src=""
      fi

      # Skip this directory if the platform has no binaries.
      local full_binpath_src="${ONION_GOPATH}/bin${platform_src}"
      if [[ ! -d "${full_binpath_src}" ]]; then
        continue
      fi

      mkdir -p "${ONION_OUTPUT_BINPATH}/${platform}"

      # Create an array of binaries to release. Append .exe variants if the platform is windows.
      local -a binaries=()
      for binary in "${targets[@]}"; do
        binary=$(basename $binary)
        if [[ $platform == "windows/amd64" ]]; then
          binaries+=("${binary}.exe")
        else
          binaries+=("${binary}")
        fi
      done

      # Move the specified release binaries to the shared ONION_OUTPUT_BINPATH.
      for binary in "${binaries[@]}"; do
        mv "${full_binpath_src}/${binary}" "${ONION_OUTPUT_BINPATH}/${platform}/"
      done

      # If no release archive was requested, we're done.
      if [[ "${ONION_RELEASE_ARCHIVE-}" == "" ]]; then
        continue
      fi

      # Create a temporary bin directory containing only the binaries marked for release.
      local release_binpath=$(mktemp -d onion.release.${ONION_RELEASE_ARCHIVE}.XXX)
      for binary in "${binaries[@]}"; do
        cp "${ONION_OUTPUT_BINPATH}/${platform}/${binary}" "${release_binpath}/"
      done

      # Create binary copies where specified.
      local suffix=""
      if [[ $platform == "windows/amd64" ]]; then
        suffix=".exe"
      fi
      for linkname in "${ONION_BINARY_COPY[@]}"; do
        local src="${release_binpath}/s2i${suffix}"
        if [[ -f "${src}" ]]; then
          cp "${release_binpath}/s2i${suffix}" "${release_binpath}/${linkname}${suffix}"
        fi
      done

      # Create the release archive.
      local platform_segment="${platform//\//-}"
      if [[ $platform == "windows/amd64" ]]; then
        local archive_name="${ONION_RELEASE_ARCHIVE}-${ONION_GIT_VERSION}-${ONION_GIT_COMMIT}-${platform_segment}.zip"
        echo "++ Creating ${archive_name}"
        for file in "${ONION_BINARY_RELEASE_WINDOWS[@]}"; do
          zip "${ONION_LOCAL_RELEASEPATH}/${archive_name}" -qj "${release_binpath}/${file}"
        done
      else
        local archive_name="${ONION_RELEASE_ARCHIVE}-${ONION_GIT_VERSION}-${ONION_GIT_COMMIT}-${platform_segment}.tar.gz"
        echo "++ Creating ${archive_name}"
        tar -czf "${ONION_LOCAL_RELEASEPATH}/${archive_name}" -C "${release_binpath}" .
      fi
      rm -rf "${release_binpath}"
    done
  )
}

# onion::make_binary_symlinks makes symlinks for the onion
# binary in _output/local/go/bin
#onion::make_binary_symlinks() {
#  platform=$(onion::host_platform)
#  if [[ -f "${ONION_OUTPUT_BINPATH}/${platform}/s2i" ]]; then
#    for linkname in "${ONION_BINARY_SYMLINKS[@]}"; do
#      if [[ $platform == "windows/amd64" ]]; then
#        cp s2i "${ONION_OUTPUT_BINPATH}/${platform}/${linkname}.exe"
#      else
#        ln -sf s2i "${ONION_OUTPUT_BINPATH}/${platform}/${linkname}"
#      fi
#    done
#  fi
#}

# onion::detect_local_release_tars verifies there is only one primary and one
# image binaries release tar in ONION_LOCAL_RELEASEPATH for the given platform specified by
# argument 1, exiting if more than one of either is found.
#
# If the tars are discovered, their full paths are exported to the following env vars:
#
#   ONION_PRIMARY_RELEASE_TAR
onion::detect_local_release_tars() {
  local platform="$1"

  if [[ ! -d "${ONION_LOCAL_RELEASEPATH}" ]]; then
    echo "There are no release artifacts in ${ONION_LOCAL_RELEASEPATH}"
    exit 2
  fi
  if [[ ! -f "${ONION_LOCAL_RELEASEPATH}/.commit" ]]; then
    echo "There is no release .commit identifier ${ONION_LOCAL_RELEASEPATH}"
    exit 2
  fi
  local primary=$(find ${ONION_LOCAL_RELEASEPATH} -maxdepth 1 -type f -name source-to-image-*-${platform}*)
  if [[ $(echo "${primary}" | wc -l) -ne 1 ]]; then
    echo "There should be exactly one ${platform} primary tar in $ONION_LOCAL_RELEASEPATH"
    exit 2
  fi

  export ONION_PRIMARY_RELEASE_TAR="${primary}"
  export ONION_RELEASE_COMMIT="$(cat ${ONION_LOCAL_RELEASEPATH}/.commit)"
}


# onion::get_version_vars loads the standard version variables as
# ENV vars
onion::get_version_vars() {
  if [[ -n ${ONION_VERSION_FILE-} ]]; then
    source "${ONION_VERSION_FILE}"
    return
  fi
  onion::onion_version_vars
}

# onion::_version_vars looks up the current Git vars
onion::onion_version_vars() {
  local git=(git --work-tree "${ONION_ROOT}")

  if [[ -n ${ONION_GIT_COMMIT-} ]] || ONION_GIT_COMMIT=$("${git[@]}" rev-parse --short "HEAD^{commit}" 2>/dev/null); then
    if [[ -z ${ONION_GIT_TREE_STATE-} ]]; then
      # Check if the tree is dirty.  default to dirty
      if git_status=$("${git[@]}" status --porcelain 2>/dev/null) && [[ -z ${git_status} ]]; then
        ONION_GIT_TREE_STATE="clean"
      else
        ONION_GIT_TREE_STATE="dirty"
      fi
    fi

    # Use git describe to find the version based on annotated tags.
    if [[ -n ${ONION_GIT_VERSION-} ]] || ONION_GIT_VERSION=$("${git[@]}" describe --tags "${ONION_GIT_COMMIT}^{commit}" 2>/dev/null); then
      if [[ "${ONION_GIT_TREE_STATE}" == "dirty" ]]; then
        # git describe --dirty only considers changes to existing files, but
        # that is problematic since new untracked .go files affect the build,
        # so use our idea of "dirty" from git status instead.
        ONION_GIT_VERSION+="-dirty"
      fi

      # Try to match the "git describe" output to a regex to try to extract
      # the "major" and "minor" versions and whether this is the exact tagged
      # version or whether the tree is between two tagged versions.
      if [[ "${ONION_GIT_VERSION}" =~ ^v([0-9]+)\.([0-9]+)([.-].*)?$ ]]; then
        ONION_GIT_MAJOR=${BASH_REMATCH[1]}
        ONION_GIT_MINOR=${BASH_REMATCH[2]}
        if [[ -n "${BASH_REMATCH[3]}" ]]; then
          ONION_GIT_MINOR+="+"
        fi
      fi
    fi
  fi
}

# Saves the environment flags to $1
onion::save_version_vars() {
  local version_file=${1-}
  [[ -n ${version_file} ]] || {
    echo "!!! Internal error.  No file specified in onion::save_version_vars"
    return 1
  }

  cat <<EOF >"${version_file}"
ONION_GIT_COMMIT='${ONION_GIT_COMMIT-}'
ONION_GIT_TREE_STATE='${ONION_GIT_TREE_STATE-}'
ONION_GIT_VERSION='${ONION_GIT_VERSION-}'
ONION_GIT_MAJOR='${ONION_GIT_MAJOR-}'
ONION_GIT_MINOR='${ONION_GIT_MINOR-}'
EOF
}

# golang 1.5 wants `-X key=val`, but golang 1.4- REQUIRES `-X key val`
onion::ldflag() {
  local key=${1}
  local val=${2}

  GO_VERSION=($(go version))

  if [[ -z $(echo "${GO_VERSION[2]}" | grep -E 'go1.5') ]]; then
    echo "-X ${ONION_GO_PACKAGE}/pkg/version.${key} ${val}"
  else
    echo "-X ${ONION_GO_PACKAGE}/pkg/version.${key}=${val}"
  fi
}

# onion::ldflags calculates the -ldflags argument for building ONION
onion::ldflags() {
  (
    # Run this in a subshell to prevent settings/variables from leaking.
    set -o errexit
    set -o nounset
    set -o pipefail

    cd "${ONION_ROOT}"

    onion::get_version_vars

    declare -a ldflags=()
    ldflags+=($(onion::ldflag "majorFromGit" "${ONION_GIT_MAJOR}"))
    ldflags+=($(onion::ldflag "minorFromGit" "${ONION_GIT_MINOR}"))
    ldflags+=($(onion::ldflag "versionFromGit" "${ONION_GIT_VERSION}"))
    ldflags+=($(onion::ldflag "commitFromGit" "${ONION_GIT_COMMIT}"))

    # The -ldflags parameter takes a single string, so join the output.
    echo "${ldflags[*]-}"
  )
}
