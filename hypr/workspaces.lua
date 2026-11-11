-- omext workspaces: Super + scroll wheel goes to the next workspace or the one
-- before only if asked for ("superScroll": true in ~/.config/omext/workspaces.json).
-- By default those keys are taken off: a scroll with Super held switched
-- workspace by accident, and the next window opened out of sight. The number
-- keys (Super + 1 ... 0) and Super + Tab are left as they are.
local config = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/omext/workspaces.json"
local f = io.open(config, "r")
local text = f and f:read("*a") or ""
if f then f:close() end
if not text:match('"superScroll"%s*:%s*true') then
  pcall(hl.unbind, "SUPER + mouse_down")
  pcall(hl.unbind, "SUPER + mouse_up")
end
