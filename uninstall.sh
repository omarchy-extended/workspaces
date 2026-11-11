#!/bin/bash
# Removes what install.sh added: Omarchy's own workspaces are back on the bar.
set -uo pipefail
shell_conf=$HOME/.config/omarchy/shell.json
if [[ -s $shell_conf ]] && grep -q '"omext.workspaces"' "$shell_conf"; then
  jq '(.bar.layout[]?[]? | select(.id == "omext.workspaces") | .id) = "omarchy.workspaces"' "$shell_conf" > "$shell_conf.tmp" && mv "$shell_conf.tmp" "$shell_conf"
fi
[[ -L $HOME/.config/omarchy/plugins/omext.workspaces ]] && rm "$HOME/.config/omarchy/plugins/omext.workspaces"
menu_conf=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
[[ -f $menu_conf ]] && sed -i "\|^ *// BEGIN omext-workspaces\$|,\|^ *// END omext-workspaces\$|d" "$menu_conf"
hypr_conf=$HOME/.config/hypr/hyprland.lua
[[ -f $hypr_conf ]] && sed -i "/^-- BEGIN omext-workspaces\$/,/^-- END omext-workspaces\$/d" "$hypr_conf" && hyprctl reload >/dev/null
echo "uninstall: done (your settings are still in ~/.config/omext/workspaces.json)"
