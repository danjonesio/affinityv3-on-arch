# Affinity on Arch Linux

Run **Affinity 3** (the unified app by Canva/Serif, Windows build) on Arch Linux with Wine — GPU
rendering, OpenCL acceleration, crisp UI, low input latency. A few hundred lines of shell you can read,
not a GUI installer.

Developed and tested on [Omarchy](https://omarchy.org) (Arch + Hyprland) with an NVIDIA RTX 3080;
everything except the optional Hyprland window rules is plain Arch.

## Quick start

```sh
git clone <this repo> ~/affinity && cd ~/affinity
cp config.example.sh config.sh      # optional: DPI, workspace, frame cap
./setup.sh                          # ~10 min; asks for sudo once (packages, ntsync)
./affinity                          # or launch "Affinity" from your app menu
```

`setup.sh` installs the packages, downloads every dependency from its upstream release (the Affinity
package from Canva's own CDN), builds the Wine prefix, installs Affinity, and registers the app-menu
entry and `.afdesign/.afphoto/.afpub` file associations. Re-run it any time; finished steps are skipped.

On Hyprland (Omarchy): `./setup.sh --hyprland` also appends window rules to `~/.config/hypr/hyprland.lua`
(see `hyprland-rules.lua`; the file is backed up first).

## Day to day

| | |
|---|---|
| `./affinity [file]` | launch (logs in `logs/`, last 20 kept) |
| `./update.sh --check` | is there a newer Affinity build on the server? |
| `./update.sh --download` | fetch and install it (previous build kept for `--rollback`) |
| `./setup.sh` | re-apply after editing `config.sh` (e.g. DPI) |
| `AFFINITY_WINE=system ./affinity` | run on the distro's Wine instead of the bundled build |

## What works

- Vector / Pixel / Layout personas, documents, export, live filters
- Renderer on the GPU (Direct3D 12 via vkd3d-proton), **OpenCL compute acceleration** (Settings → Performance)
- Sharp UI with ClearType and DPI scaling, colour picker under Wayland, panels, shortcuts

## What doesn't

- **Canva account sign-in.** It needs Microsoft WebView2, which doesn't run under Wine. Everything that
  doesn't require an account works; Canva-integration features don't. Don't press "Sign out".
- Help / web-based dialogs (same reason).
- Undocking panels can crash the app (Wine/WPF limitation) — keep panels docked, save a studio preset.
- Wine's native Wayland driver (`AFFINITY_WAYLAND=1`): wrong geometry at non-96 DPI and a clipboard
  crash on current Hyprland. XWayland is used by default.

## How it works (and why each piece is there)

1. **Wine runtime** — [ElementalWarrior's Wine](https://github.com/ryzendew/Affinity-Wine-Builder)
   11.12 (prebuilt). Stock Wine ≥ 10.17 runs Affinity fine, but its `opencl.dll` hides OpenCL extensions
   it can't proxy, so Affinity refuses hardware acceleration ("Unsupported Graphics Card"). The
   ElementalWarrior build exposes the real device. Prefix setup itself uses the distro Wine + winetricks.
2. **Prefix** — `remove_mono vcrun2022 dotnet48 corefonts tahoma win11 renderer=vulkan fontsmooth=rgb`.
3. **Affinity payload** — the MSIX is a zip; its `App/` folder *is* the installed program, so it's
   extracted straight into `Program Files/Affinity/Affinity` (the MSIX can't be executed under Wine).
4. **WinRT metadata** — `.winmd` files in `system32/WinMetadata` plus
   [ElementalWarrior's `wintypes.dll` shim](https://github.com/ElementalWarrior/wine-wintypes.dll-for-affinity)
   so the .NET side can resolve `Windows.*` types.
5. **DXVK** (D3D9/D3D11) — wined3d's Vulkan backend fails to compile Affinity's shaders
   (`shader_spirv_compile_shader ret -5`): pixelated, half-drawn UI.
6. **vkd3d-proton** (D3D12) — Affinity renders the canvas with D3D12 and shares it into the WPF UI;
   Wine's built-in d3d12 leaves stale GPU memory (your wallpaper) ghosted on the page.
7. **[AffinityPluginLoader](https://github.com/noahc3/AffinityPluginLoader) + WineFix** — patched
   `d2d1.dll`, synchronous font enumeration (startup-crash fix), preferences saving, Wayland colour
   picker, and it suppresses the dead WebView2 sign-in prompt. The launcher runs `AffinityHook.exe`.
8. **`DXVK_CONFIG` (`env.sh`)** — WPF draws the UI chrome through D3D9 and DXVK can't do WPF's partial
   presents ([dxvk #2542](https://github.com/doitsujin/dxvk/issues/2542)): toolbars go black after a
   resize until hovered. Reporting shader model 1 makes WPF use its software rasterizer for the chrome
   only. `syncInterval=0` + `maxFrameLatency=1` + `VKD3D_SWAPCHAIN_LATENCY_FRAMES=1` remove the
   5-frame swapchain queue that made dragging feel laggy; the frame cap keeps it at display rate.
9. **ntsync** — the kernel module is loaded and persisted; Wine 10+ picks `/dev/ntsync` up
   automatically. Large responsiveness win for a .NET/WPF app.
10. **Hyprland rules** (optional) — the XWayland window carries an alpha channel that Hyprland would
    composite as see-through (`force_rgbx`); dialogs float; main window on a workspace of your choice.

## Hardware notes

- NVIDIA: `opencl-nvidia` is installed for you. Tested on an RTX 3080.
- AMD / Intel: `setup.sh` installs `rocm-opencl-runtime` / `intel-compute-runtime`; untested — reports welcome.
- vkd3d-proton needs a Vulkan 1.3 capable GPU and driver.

## Troubleshooting

- **Affinity won't start, no window** — an earlier instance may be hung (Affinity is single-instance):
  `pkill -9 -f '[A]ffinity\.exe'; pkill -9 -x wineserver`, then launch again. Look at the newest file in
  `logs/`.
- **Hardware acceleration says "Unsupported Graphics Card"** — you're on the system Wine
  (`AFFINITY_WINE=system`) or the OpenCL runtime package isn't installed.
- **UI too small/large** — set `AFFINITY_DPI` in `config.sh` (96/120/144), re-run `./setup.sh`.
- **Long sessions** — one 16-minute session was seen exhausting X resource IDs (`_XAllocID` assertion)
  and hanging; the frame cap was added afterwards and it hasn't recurred. If you can reproduce it,
  `xrestop` output over time would help.

## Credits

[affinity.liz.pet](https://affinity.liz.pet/) (manual guide), [AffinityOnLinux](https://github.com/ryzendew/AffinityOnLinux)
(Wine builds, WinMetadata bundle, DXVK/vkd3d settings), [noahc3/AffinityPluginLoader](https://github.com/noahc3/AffinityPluginLoader),
[ElementalWarrior](https://github.com/ElementalWarrior). Affinity is a trademark of Canva; this project
downloads the official package and redistributes nothing of theirs.

MIT licence.
