# Affinity on Arch Linux

Run **Affinity 3** (the unified app by Canva/Serif, Windows build) on Arch Linux with Wine — GPU
rendering, OpenCL acceleration, crisp UI, low input latency. A few hundred lines of shell you can read,
not a GUI installer.

Developed and tested on [Omarchy](https://omarchy.org) (Arch + Hyprland) with an NVIDIA RTX 3080;
everything except the optional Hyprland window rules is plain Arch.

## Quick start

```sh
git clone <this repo> ~/affinity && cd ~/affinity
cp config.example.sh config.sh      # optional: workspace, DPI override (auto by default)
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
| `./setup.sh` | re-apply after editing `config.sh` (DPI is applied on launch; no re-setup needed) |
| `AFFINITY_WINE=system ./affinity` | run on the distro's Wine instead of the bundled build |

## What works

- Vector / Pixel / Layout personas, documents, export, live filters
- Renderer on the GPU (Direct3D 12 via vkd3d-proton). **OpenCL compute acceleration** on NVIDIA
  (Settings → Performance); Intel OpenCL is off by default because it hangs the splash.
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
- Intel: `intel-compute-runtime` is installed but **OpenCL is disabled at launch**.
  On Lunar Lake (Arc 130V/140V) Intel NEO + vkd3d D3D12 sharing hangs the splash
  so the window cannot be closed. `env.sh` hides the OpenCL ICD, forces D3D12 FL 12.0,
  and disables `VK_KHR_present_wait`. The canvas still renders on the GPU via D3D12;
  set `AFFINITY_OPENCL=1` in `config.sh` to retry compute. Hyprland rules
  (`./setup.sh --hyprland`) are required or the XWayland window is composited
  fully transparent.
- AMD: `setup.sh` installs `rocm-opencl-runtime`; same present_wait workaround as Intel.
- vkd3d-proton needs a Vulkan 1.3 capable GPU and driver.

## Troubleshooting

- **Affinity won't start, no window** — an earlier instance may be hung (Affinity is single-instance):
  `pkill -9 -f '[A]ffinity\.exe'; pkill -9 -x wineserver`, then launch again. Look at the newest file in
  `logs/`.
- **Stuck on the splash, window won't close** — usually Intel OpenCL (NEO hanging on D3D12 sharing)
  or a leftover hung instance. Kill it with the command above. `env.sh` now hides the Intel ICD
  unless `AFFINITY_OPENCL=1`. On Hyprland, run `./setup.sh --hyprland` so the XWayland window is
  forced opaque; without those rules the main window is invisible and eats input.
- **Hardware acceleration says "Unsupported Graphics Card"** — you're on the system Wine
  (`AFFINITY_WINE=system`) or the OpenCL runtime package isn't installed.
- **UI too small/large** — Omarchy runs XWayland unscaled (`force_zero_scaling`), so Wine
  must use `LogPixels = 96 × monitor scale`. Default is `AFFINITY_DPI=auto`, which reads
  the Hyprland scale of the workspace Affinity opens on, then caps it so the New Document
  dialog still fits the monitor's usable area (this 2880x1800 laptop panel at 2x is only
  1440x900 logical, so it gets 168 rather than 192). Pin a number in `config.sh` if you
  want it bigger/smaller; it applies on the next launch, no `./setup.sh`.
- **Dialogs poke behind the top bar, combo-box menus open in the middle of the screen** —
  the DPI is too high for the screen: the New Document window is larger than the desktop,
  Hyprland centres it over the bar and WPF has nowhere to anchor its popups. Auto DPI now
  prevents this; if you pinned `AFFINITY_DPI`, lower it a step. `config.sh` is gitignored, so the desktop 3080 and this
  laptop can disagree. An ultrawide is picked up automatically if workspace 5 lives
  on that monitor — relaunch after you plug it in.
- **Long sessions** — one 16-minute session was seen exhausting X resource IDs (`_XAllocID` assertion)
  and hanging; the frame cap was added afterwards and it hasn't recurred. If you can reproduce it,
  `xrestop` output over time would help.

## Credits

[affinity.liz.pet](https://affinity.liz.pet/) (manual guide), [AffinityOnLinux](https://github.com/ryzendew/AffinityOnLinux)
(Wine builds, WinMetadata bundle, DXVK/vkd3d settings), [noahc3/AffinityPluginLoader](https://github.com/noahc3/AffinityPluginLoader),
[ElementalWarrior](https://github.com/ElementalWarrior). Affinity is a trademark of Canva; this project
downloads the official package and redistributes nothing of theirs.

MIT licence.
