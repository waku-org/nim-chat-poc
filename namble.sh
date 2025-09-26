#!/bin/bash

# This script provides a 'nimble install' like interface for the nimbus build system.
# 
# Usage: 
#    ./namble.sd <nimble_pkg>
#
#
# The script
#  - accesses https://nimble.directory/
#  - extracts the <author>/<pkg> from the project directory
#  - invokes add_submodule.

# Check if a pkg argument was provided
if [ -z "$1" ]; then
  echo "Usage: $0 <pkg>"
  exit 1
fi


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADD_SCRIPT="$SCRIPT_DIR/vendor/nimbus-build-system/scripts/add_submodule.sh"

echo "$ADD_SCRIPT"


echo "Fetching nimble package $1"

URL="https://nimble.directory/pkg/$1"

auth_pkg=$(curl -s "$URL" \
  | grep -o '<p> <a href="https://github.com/[^"]*"' \
  | sed -E 's#.*github.com/([^"]*)".*#\1#'
)


if [ -z "$auth_pkg" ]; then
  echo "No nimble package was found with name <$1>"
  exit 1
fi

echo Found "<$auth_pkg>"

$ADD_SCRIPT $auth_pkg

make update
