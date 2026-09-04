-- Hyprland window rules for Affinity (optional). setup.sh --hyprland appends this to
-- ~/.config/hypr/hyprland.lua on Omarchy; on plain Hyprland translate to hl.window_rule / conf syntax.
--
-- The XWayland window carries an alpha channel that Hyprland would composite as see-through;
-- force it opaque and opt out of Omarchy's default translucency.
o.window({ class = "^(affinity\\.exe)$" }, {
  tag = "-default-opacity",
  opacity = "1 1",
  force_rgbx = true,
  no_blur = true,
})
-- Dialogs (Welcome, Settings, New Document, splash - anything not titled plain "Affinity") float.
o.window({ class = "^(affinity\\.exe)$", title = "^(?!Affinity$).*" }, { float = true, center = true })
-- Main window on its own workspace (edit the number, or delete this line).
o.window({ class = "^(affinity\\.exe)$" }, { workspace = "@WORKSPACE@" })
