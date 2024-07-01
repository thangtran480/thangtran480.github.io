#!/usr/bin/env bash

# ==============================================================================
# Copyright (C) 2021-2023 Potherca
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
# ==============================================================================
# There are a few standards this code tries to adhere to, these are listed below.
#
# - Code follows the BASH style-guide described at:
#   http://guides.dealerdirect.io/code-styling/bash/
#
# - Variables are named using an adaption of Systems Hungarian explained at:
#   http://blog.pother.ca/VariableNamingConvention
#
# ==============================================================================

set -o errexit  # Exit script when a command exits with non-zero status.
set -o errtrace # Exit on error inside any functions or sub-shells.
set -o nounset  # Exit script on use of an undefined variable.
set -o pipefail # Return exit status of the last command in the pipe that exited with a non-zero exit code

# ==============================================================================
#                       Git Clone All Projects in GitHub Organisation
# ------------------------------------------------------------------------------
## Usage: $0 [-dhu] <github-domain> <organisation-id> <github-token>
##
## Where:
##       - <github-domain> is the domain where github lives (for instance: 'github.com')
##       - <organisation-id> is the ID of the organisation who's repos should be cloned
##       - <github-token> is the API access token to make REST API calls with
##
## Options:
##   -d|--dry-run   Only list the repositories, without actually cloning them
##   -h|--help      Print this help dialogue and exit
##   -u|--user      The given ID is a user, not an organisation
##
## The repositories will be cloned into a sub-directory under the path from Where
## this script has been called. The repository will be cloned into ./${organisation-id}/${repo-name}
##
## The git and cUrl executable can be overridden by setting their respective environmental variable
## before calling this script:
##
##        CURL=/usr/local/curl GIT=/usr/local/git-plus $0 <github-domain> <organisation-id> <github-token>
# ==============================================================================

: readonly "${CURL:=curl}"
: readonly "${GIT:=git}"

usage() {
    local sScript sUsage

    readonly sScript="$(basename "$0")"
    readonly sUsage="$(grep '^##' <"$0" | cut -c4-)"

    echo -e "${sUsage//\$0/${sScript}}"
}

github-clone-projects() {

    local -a aParameters aRepos
    local bIsUser bDryRun
    local sDirectory sGithubDomain sGithubToken sId sRepo sRepos

    call-url() {
        local sHeaderResult sPaginationUrl sPrevious sResult sUrl

        readonly sUrl="${1?One parameter required: <url> [previous-content]}"
        readonly sPrevious="${2:-''}"

        sHeaderResult=$("${CURL}" \
            --head \
            --header "Accept: application/vnd.github.v3+json" \
            --header "Authorization: token ${sGithubToken}" \
            --request 'GET' \
            --silent \
            "${sUrl}")

        sResult=$("${CURL}" \
            --header "Accept: application/vnd.github.v3+json" \
            --header "Authorization: token ${sGithubToken}" \
            --silent \
            "${sUrl}")

        sPaginationUrl=$(echo "${sHeaderResult}" \
            | grep -oE '<[^>]+>; rel="next"' \
            | grep -oE 'https?://[^>]+'
        ) || true

        if [[ "${sPaginationUrl}"  == '' ]]; then
            printf '%s\n%s' "${sPrevious}" "${sResult}"
        else
            call-url "${sPaginationUrl}" "${sResult}"
        fi
    }

    call-api() {
        local sSubject

        readonly sSubject="${1?One parameter required: <api-subject>}"

        call-url "https://api.${sGithubDomain}/${sSubject}?per_page=100"
    }

    fetch-projects() {
      local iId sSubject

      readonly sSubject="${1?Two parameters required: <subject> <id>}"
      readonly iId="${2?Two parameters required: <subject> <id>}"

      # @TODO: Add param that allows skipping archived repos
      # @TODO: Add param that allows skipping forks

      call-api "${sSubject}/${iId}/repos" \
        | grep -E -o '"ssh_url"\s*:\s*"[^"]+"' \
        | cut -d '"' -f4
    }

    fetch-organisation-projects() {
      local -r iId="${1?One parameters required: <id>}"
      fetch-projects 'orgs' "${iId}"
    }

    fetch-user-projects() {
      local -r iId="${1?One parameters required: <id>}"
      fetch-projects 'users' "${iId}"
    }

    bIsUser=false
    bDryRun=false
    aParameters=()

    for arg in "$@";do
      case $arg in
        -h|--help )
          usage
          exit
        ;;

        -d|--dry-run )
          readonly bDryRun=true
          shift
        ;;

        -u|--user )
          # @TODO: Is there a way we can detect if this is a user or organisation?
          readonly bIsUser=true
          shift
        ;;

        * )
          aParameters+=( "$1" )
          shift
        ;;
      esac
    done
    readonly aParameters

    readonly sGithubDomain="${aParameters[0]?Three parameters required: <github-domain> <organisation-id> <github-token>}"
    readonly sId="${aParameters[1]?Three parameters required: <github-domain> <organisation-id> <github-token>}"
    readonly sGithubToken="${aParameters[2]?Three parameters required: <github-domain> <organisation-id> <github-token>}"

    if [[ "${bIsUser}" = 'true' ]];then
      readonly sRepos=$(fetch-user-projects "${sId}")
    else
      readonly sRepos=$(fetch-organisation-projects "${sId}")
    fi

    aRepos=()
    for sRepo in ${sRepos[*]}; do
      aRepos+=("${sRepo}")
    done

    echo ' =====> Found ' ${#aRepos[@]} ' repositories'

    for sRepo in "${aRepos[@]}"; do
      # Grab repo name
      sDirectory="$(echo "${sRepo}" | grep -o -E ':(.*)\.')"
      # Lowercase the name
      sDirectory="$(echo "${sDirectory}" | tr '[:upper:]' '[:lower:]')"
      # Prepend the current location
      sDirectory="$(realpath --canonicalize-missing --relative-to=./ "${sDirectory:1:-1}")"

      if [[ -d "${sDirectory}" ]];then
        echo " -----> Skipping '${sRepo}', directory '${sDirectory}' already exists"
      else
        echo " -----> Cloning '${sRepo}' into directory '${sDirectory}'"

        if [[ "${bDryRun}" != 'true' ]];then
          mkdir -p "${sDirectory}"
          "${GIT}" clone --recursive "${sRepo}" "${sDirectory}" \
            || {
              rm -rf "${sDirectory}"
              echo -e "\n ! ERROR !\n           Could not clone ${sRepo}"
          }
          echo ""
        fi
      fi
    done
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  export -f github-clone-projects
else
  github-clone-projects "${@}"
  exit $?
fi

#EOF
