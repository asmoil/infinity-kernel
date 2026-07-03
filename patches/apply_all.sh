#!/bin/bash
# apply_all.sh - Safe patch application
# $1 = kernel source root
safe_sed() {
  local file="$1" old="$2" new="$3"
  [ -f "$file" ] && sed -i "s|$old|$new|g" "$file"
}

echo "apply_all.sh: no additional patches"
