#!/bin/bash
#
# Deprecated: run wildfly-lib.sh instead, which has every function this script had:
#   wildfly-lib.sh -e ENV_FILE FUNCTION...
# Kept so that the old form, app-setup.sh ENV_FILE FUNCTION..., still works.

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 ENV_FILE FUNCTION..." >&2
  echo "Deprecated: use wildfly-lib.sh -e ENV_FILE FUNCTION... (--help lists the functions)." >&2
  echo "Running every function when none is named is no longer supported: name the ones you need." >&2
  exit 2
fi

env_file=$1
shift
exec "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/wildfly-lib.sh" -e "${env_file}" "$@"
