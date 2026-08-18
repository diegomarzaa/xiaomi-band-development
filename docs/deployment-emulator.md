# Emulator deployment reference

This page is the short command reference. The conceptual explanation and the image-selection caveats live in [`development-guide.md`](development-guide.md).

## Preconditions

Start a Vela emulator in AIoT-IDE or with the executable/profile created by the toolkit. Then confirm that ADB sees it:

```bash
adb devices -l
```

The expected entry resembles `emulator-5554 device`. The serial can differ, so pass the real value with `--serial` instead of changing the script.

Install the helper dependencies once:

```bash
cd scripts
npm install
cd ..
```

## Build and deploy with the repository helper

```bash
./scripts/emu-deploy.sh --project <project-dir>
```

Options:

```text
--project <dir>       Vela project containing src/manifest.json
--serial <serial>     Emulator ADB serial, default emulator-5554
--no-build            Reuse the newest RPK in <project-dir>/dist
--no-screenshot       Skip the post-deployment gRPC screenshot
--grpc-port <port>    Override the gRPC port, default auto-detect/8554
```

The helper performs these operations:

1. Reads the package name from `src/manifest.json`.
2. Runs `npm run build`, unless `--no-build` is present.
3. Pushes the newest `.rpk` to the emulator's `/data/quickapp/app/` directory.
4. Extracts the package and launches it with the Vela `vapp` runtime.
5. Requests a screenshot through gRPC unless disabled.

The `/data/...` paths above belong to the emulator filesystem. They are not paths that you need to create on the host.

## Individual commands

```bash
adb -s <emu-serial> get-state
adb -s <emu-serial> push <project-dir>/dist/<package>.rpk /data/quickapp/app/<package>.rpk
adb -s <emu-serial> shell unzip -o /data/quickapp/app/<package>.rpk -d /data/quickapp/app/<package>
adb -s <emu-serial> shell "vapp app/<package> &"
```

For a Vela 5 `vela-watch` image, the toolkit can also use:

```bash
adb -s <emu-serial> shell pm install <rpk-path-visible-to-the-emulator>
adb -s <emu-serial> shell am start <package-name>
adb -s <emu-serial> shell am stop <package-name>
```

The install method depends on the image and toolkit version. If `vapp` or `pm install` reports success but the page does not open, inspect the emulator log and use the other launch path.

## gRPC control

```bash
node scripts/emulator-grpc.js status
node scripts/emulator-grpc.js screenshot "${TMPDIR:-/tmp}/vela-screen.png"
node scripts/emulator-grpc.js click <x> <y>
node scripts/emulator-grpc.js tap <x> <y>
node scripts/emulator-grpc.js swipe <x1> <y1> <x2> <y2> [milliseconds]
```

Use `click` for Vela `onclick` handlers. `tap` sends a touch event and may not trigger the same handler in the emulator. The coordinates are physical display pixels. On a Band 10 profile, use the 212 × 520 coordinate space.

The helper searches common AIoT-IDE extension directories for `emulator_controller.proto`. If auto-detection fails:

```bash
node scripts/emulator-grpc.js \
  --proto-dir <aiot-emulator-extension>/proto \
  screenshot "${TMPDIR:-/tmp}/vela-screen.png"
```

You can also set `VELA_PROTO_DIR` and `GRPC_PORT` in the environment. The script uses no project-specific absolute path.

## Image and profile rules

`npm install` provides the JavaScript controller. `npx aiot initEmulatorEnv` downloads the runtime and system images. Create a custom profile with width 212, height 520, density 320, shape `pill-shaped`, and flavor `band` for Band 10 layout work.

The fixed `vela-miwear-watch-5.0` image can display a different internal watch layout through a custom viewport. The adaptable `vela-watch` image is the safer choice for custom dimensions when the installed toolkit offers it. Xiaomi documents the distinction in [Multi-Screen Adaptation](https://iot.mi.com/vela/quickapp/en/tools/debug/multi-screens.html).

## Known toolkit 2.0.5 behavior

The interactive `aiot createVVD` command can abort while checking a new name, and `aiot start` can time out after the emulator has booted and installed the RPK. Check for these independent signals before deleting a profile or rebuilding:

```text
Setting display ... to 212x520
InstallState_Finished / success 0
Start App loop
```

If the wrapper times out, keep the emulator running, wait for `adb devices`, and use the individual `pm install`/`am start` commands above. This behavior belongs to that toolkit version, not to the `.rpk` format.

## Official references

- [AIoT-IDE development and simulator workflow](https://iot.mi.com/vela/quickapp/en/guide/start/use-ide.html)
- [Multi-screen emulator creation and custom skins](https://iot.mi.com/vela/quickapp/en/tools/debug/multi-screens.html)
- [Vela project structure](https://iot.mi.com/vela/quickapp/en/guide/start/project-overview.html)
- [Packaging applications](https://iot.mi.com/vela/quickapp/en/tools/release/start.html)
