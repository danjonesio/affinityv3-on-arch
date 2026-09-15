-- Hyprland window rules for Affinity (optional). setup.sh --hyprland appends this to
-- ~/.config/hypr/hyprland.lua on Omarchy; on plain Hyprland translate to hl.window_rule / conf syntax.
--
-- The XWayland window carries an alpha channel that Hyprland would composite as see-through;
-- force it opaque and opt out of Omarchy's default translucency.
-- Title negation uses Hyprland's RE2 "negative:" prefix (lookahead is not supported).
o.window({ class = "^(affinity\\.exe)$" }, {
  tag = "-default-opacity",
  opacity = "1 1",
  force_rgbx = true,
  opaque = true,
  no_blur = true,
})
-- Dialogs (Welcome, Settings, New Document, splash - anything not titled plain "Affinity") float.
-- RE2 has no lookahead; "negative:" inverts the match. Empty-title splash/Welcome is included.
-- No "center": menus and combo-box popups are override-redirect X11 windows with the same class
-- and an empty title, and Hyprland >= 0.56 applies the rule to them too, dropping every dropdown
-- in the middle of the screen. Wine already centres real dialogs over their owner window.
o.window({ class = "^(affinity\\.exe)$", title = "negative:^Affinity$" }, { float = true })
-- Main window on its own workspace (edit the number, or delete this line).
o.window({ class = "^(affinity\\.exe)$" }, { workspace = "@WORKSPACE@" })
