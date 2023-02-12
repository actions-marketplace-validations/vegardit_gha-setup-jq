# SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com) and contributors
# SPDX-FileContributor: Sebastian Thomschke, Vegard IT GmbH
# SPDX-License-Identifier: Apache-2.0
#
# https://github.com/vegardit/gha-setup-jq/
#
set -euo pipefail

function get_installed_version() {
  "${1:-$app_home/$app_target_bin}" --version | cut -d- -f2
}

INPUTS_VERSION_LOWERCASE="$(tr '[:upper:]' '[:lower:]' <<<"$INPUTS_VERSION")"

if [[ $INPUTS_VERSION_LOWERCASE == 'any' ]] && hash jq &>/dev/null; then

  # set outputs
  echo "need_cache_update=false" | tee -a "$GITHUB_OUTPUT"
  case "$RUNNER_OS" in
    Windows) echo "path=$(cygpath -w "$(which jq)")" | tee -a "$GITHUB_OUTPUT" ;;
    *)       echo "path=$(which jq)" | tee -a "$GITHUB_OUTPUT" ;;
  esac
  echo "version=$(get_installed_version "$(which jq)")" | tee -a "$GITHUB_OUTPUT"

else

  APP_REPO_ROOT=https://github.com/stedolan/jq

  case "$RUNNER_OS" in
    macOS)
      app_home="$RUNNER_TEMP/jq"
      app_target_bin=jq
      case "$(machine)" in
        *arm*) echo "ERROR: Unsupported architecture $(machine)"; exit 1 ;;
            *) app_source_bin='jq-osx-amd64' ;;
      esac
      ;;
    Linux)
      app_home="$RUNNER_TEMP/jq"
      app_target_bin=jq
      case $(uname -m) in # https://stackoverflow.com/questions/45125516/possible-values-for-uname-m
        i386|i686) app_source_bin='jq-linux32' ;;
           x86_64) app_source_bin='jq-linux64' ;;
                *) echo "ERROR: Unsupported architecture $(uname -m)"; exit 1 ;;
      esac
      ;;
    Windows)
      app_home="$(cygpath "$RUNNER_TEMP")/jq"
      app_target_bin=jq.exe
      app_source_bin='jq-win64.exe'
      ;;
  esac

  echo "app_home: $app_home"
  echo "app_source_bin: $app_source_bin"
  echo "app_target_bin: $app_target_bin"

  function get_latest_version() {
    curl -sSfL --max-time 5 -o /dev/null -w '%{url_effective}' $APP_REPO_ROOT/releases/latest | grep -o '[^/]*$' | cut -d- -f2
  }

  app_downloaded=false

  function download_app() {
    app_download_url="$APP_REPO_ROOT/releases/download/jq-$1/$app_source_bin"
    echo "Downloading [$app_download_url]..."
    mkdir -p "$app_home"
    curl -fsSL --max-time 10 --retry 3 --retry-delay 5 -o "$app_home/$app_target_bin" "$app_download_url"
    chmod 777 "$app_home/$app_target_bin"
    app_downloaded=true
  }

  case "$INPUTS_VERSION_LOWERCASE" in
    any)
      if [[ ! -f "$app_home/$app_target_bin" ]]; then
        latest_app_version=$(get_latest_version)
        download_app "$latest_app_version"
      fi
      ;;
    latest)
      if [[ -f "$app_home/$app_target_bin" ]]; then
        latest_app_version=$(get_latest_version)
        if [[ $latest_app_version != "$(get_installed_version)" ]]; then
          download_app "$latest_app_version"
        fi
      else
        download_app "$(get_latest_version)"
      fi
      ;;
    *) # install specific release
      if [[ -f "$app_home/$app_target_bin" ]]; then
        if [[ $(get_installed_version) != "v$INPUTS_VERSION" ]]; then
          download_app "$INPUTS_VERSION"
        fi
      else
        download_app "$INPUTS_VERSION"
      fi
      ;;
  esac

  echo "$RUNNER_TEMP/jq" >> "$GITHUB_PATH"

  # prepare cache update
  if [[ $INPUTS_USE_CACHE == 'true' && ${ACT:-} != 'true' ]]; then # $ACT is set when running via nektos/act
    if [[ $app_downloaded == 'true' ]]; then
      if [[ $CACHE_HIT == 'true' ]]; then
        gh extension install actions/gh-actions-cache || true
        gh actions-cache delete "$CACHE_CACHE_KEY" --confirm || true
      fi
      need_cache_update=true
    else
      need_cache_update=false
    fi
  else
    need_cache_update=false
  fi

  # set outputs
  echo "need_cache_update=$need_cache_update" | tee -a "$GITHUB_OUTPUT"
  case "$RUNNER_OS" in
    Windows) echo "path=$(cygpath -w "$app_home/$app_target_bin")" | tee -a "$GITHUB_OUTPUT" ;;
    *)       echo "path=$app_home/$app_target_bin" | tee -a "$GITHUB_OUTPUT" ;;
  esac
  echo "version=$(get_installed_version)" | tee -a "$GITHUB_OUTPUT"

fi