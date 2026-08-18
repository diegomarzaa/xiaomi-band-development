# Developing Xiaomi Vela applications from scratch

This guide describes the full path from an empty directory to a working `.rpk` package on a Xiaomi Smart Band 10. It covers the Vela application model, project structure, screen sizing, native features, packaging, emulator setup, real-device installation, and the failure modes found while testing a real application.

The commands use paths relative to the repository or to the project directory. Replace placeholders such as `<project-dir>`, `<package-name>`, and `<phone-serial>` with values from your machine. The guide does not assume a particular home directory.

## 1. The model to keep in mind

A Vela application has three layers:

1. **Vela OS** runs on the wearable. Xiaomi describes Vela as an embedded software platform based on NuttX RTOS.
2. **The Vela JS Quick App runtime** loads an application package, creates the page tree, runs JavaScript, and exposes selected system interfaces.
3. **Your project** contains `.ux` pages, `manifest.json`, assets, and JavaScript modules. The build tool compiles these files into an `.rpk` package.

The package is an application artifact, not an Android APK. The phone and Mi Fitness act as the transport path to the band. A USB-connected phone therefore appears in `adb devices`, while the band itself usually does not appear as a normal Android ADB target.

Read Xiaomi's [Vela overview](https://iot.mi.com/vela/quickapp/en/guide/) and [framework introduction](https://iot.mi.com/vela/quickapp/en/guide/framework/) for the official terminology.

## 2. What you need

### Required for source development

- Node.js and npm. The examples in this repository use the `aiot-toolkit` package supplied by the Vela toolchain.
- A shell capable of running Bash scripts.
- Git.
- An editor. [AIoT-IDE](https://iot.mi.com/vela/quickapp/en/guide/start/use-ide.html) provides project templates, simulator management, debugging, and packaging. You can also edit and build from a terminal.

### Required for the emulator

- AIoT-IDE or the npm toolkit package.
- The Vela emulator runtime and at least one system image. Installing the npm package alone does not install these large images.
- A working local display if you want the graphical emulator window. A headless environment can still be useful for ADB and gRPC checks, but it cannot show the normal preview window.

### Required for a real wearable

- An Android phone with USB or wireless ADB enabled.
- Mi Fitness installed and paired with the band.
- Android platform tools, including `adb`.
- `javac` and `d8` for the repository's phone-side deployment helper. The helper accepts `ANDROID_HOME` or `ANDROID_SDK_ROOT`, and otherwise checks the conventional `Android/Sdk` and `Library/Android/sdk` locations under the current user's home directory. It also accepts a project and phone serial on the command line.
- Python 3, because the deployment script parses the Android UI dump with the standard XML library.

### Optional for release signing

- OpenSSL. Development packages use the toolkit's debug signing path. A release package needs the `sign/private.pem` and `sign/certificate.pem` files described in Xiaomi's [packaging guide](https://iot.mi.com/vela/quickapp/en/tools/release/start.html).

Check the tools before starting:

```bash
node --version
npm --version
git --version
adb version
javac -version
d8 --version
openssl version
```

The last three commands matter only for the real-device and release paths.

## 4. Create a new application

### Option A: create a project with AIoT-IDE

1. Open AIoT-IDE.
2. Choose **File → New Project**.
3. Choose the **Watch** project type.
4. Pick a template. The basic, list, settings, and development-example templates are useful starting points.
5. Choose a project name and directory.
6. Let the IDE install the generated npm dependencies.

Xiaomi documents this flow in [Create a New Project](https://iot.mi.com/vela/quickapp/en/tools/project/creat-project.html) and describes the generated files in [Project Overview](https://iot.mi.com/vela/quickapp/en/guide/start/project-overview.html).

### Option B: start from an empty directory

The smallest useful project has a package file and a `src/` tree. A package file can look like this:

```json
{
  "name": "my-vela-app",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "aiot build",
    "start": "aiot start"
  },
  "devDependencies": {
    "aiot-toolkit": "2.0.5"
  }
}
```

Create the directories and install the dependency with npm:

```bash
mkdir -p my-vela-app/src/pages/index my-vela-app/src/common
cd my-vela-app
npm install
```

The exact toolkit version belongs in `package-lock.json`. Keep it under version control so another developer builds with the same compiler. Newer toolkit releases may change emulator commands or generated output; check the package's own help before copying a command from an older project.

Create `src/manifest.json` before writing pages:

```json
{
  "package": "com.example.myvelaapp",
  "name": "My App",
  "versionName": "1.0.0",
  "versionCode": 1,
  "minPlatformVersion": 1000,
  "icon": "/common/icon.png",
  "deviceTypeList": ["watch"],
  "features": [
    { "name": "system.router" }
  ],
  "config": {
    "logLevel": "log",
    "designWidth": 212
  },
  "router": {
    "entry": "pages/index",
    "pages": {
      "pages/index": { "component": "index" }
    }
  }
}
```

The `package` value must be unique on the band. Treat `versionCode` as an install version, not a marketing label: increase it whenever the band needs to accept a new build. Xiaomi lists the field meanings in the [manifest reference](https://iot.mi.com/vela/quickapp/en/guide/framework/manifest.html).

## 5. Understand a `.ux` page

Vela pages combine a template, script, and style block. A minimal page looks like this:

```html
<template>
  <div class="page">
    <text class="title">{{ message }}</text>
    <text onclick="handleClick">Tap me</text>
  </div>
</template>

<script>
export default {
  private: {
    message: "Hello Band"
  },

  handleClick() {
    this.message = "Clicked"
  }
}
</script>

<style>
.page {
  width: 212px;
  height: 520px;
  flex-direction: column;
  background-color: #000000;
}

.title {
  color: #ffffff;
  font-size: 20px;
}
</style>
```

Important rules:

- Put visible text inside `<text>`.
- Register a page in `manifest.json` before navigating to it.
- Use `private` page data for values that the template displays.
- Vela JavaScript runs inside the wearable runtime. It is not Node.js, so do not import `fs`, `path`, or other Node modules in a page.
- Use relative imports for JavaScript modules and absolute app-resource paths such as `/common/icon.png` for assets when a module can be copied during compilation.
- Use the lifecycle hooks documented by Xiaomi, such as `onInit`, `onShow`, `onHide`, and `onDestroy`, instead of assuming a browser lifecycle.

Read Xiaomi's [script guide](https://iot.mi.com/vela/quickapp/en/guide/framework/script/), [project structure reference](https://iot.mi.com/vela/quickapp/en/guide/framework/project-structure.html), and [UI guide](https://iot.mi.com/vela/quickapp/en/guide/start/user-interface.html).

## 6. Design for Xiaomi Smart Band 10

The Xiaomi Smart Band 10 display is 212 × 520 physical pixels. For a project whose design draft uses the same width, set:

```json
{
  "config": {
    "designWidth": 212
  }
}
```

Then use the design coordinates directly in Vela styles. For example, a full-width content area is `width: 212px`, and a 12-pixel side margin leaves `188px` for the content.

`designWidth` is the reference width for Vela's `px` unit. It is not the same thing as the screen density. The toolkit scales the design to the actual display width. The framework uses a border-box layout model, so padding and borders count inside the declared width. A `width: 212px` element with 12-pixel left and right padding still occupies 212 design pixels.

That last rule matters on a narrow band. If a card declares 188px and also adds 13px of horizontal padding, the card still occupies 188px. Older web-CSS assumptions about content-box sizing produce unnecessary overflow.

Build a layout around the real capsule shape:

```css
.page {
  width: 212px;
  height: 520px;
  padding-left: 12px;
  padding-right: 12px;
  flex-direction: column;
  align-items: center;
}

.content {
  width: 188px;
}
```

Prefer flex layout, explicit heights for list items, and short labels. Test long strings on the physical band because the emulator's font set and rendering performance differ from the product firmware.

Xiaomi documents the [box model and length units](https://iot.mi.com/vela/quickapp/en/guide/framework/style/page-style-and-layout.html), [responsive screen adaptation](https://iot.mi.com/vela/quickapp/en/guide/multi-screens/specs.html), and [multi-screen emulator creation](https://iot.mi.com/vela/quickapp/en/tools/debug/multi-screens.html).

## 7. Add native features

Vela features follow one consistent pattern:

1. Add the feature name to the `features` array in `manifest.json`.
2. Import the module in the `.ux` script.
3. Call the API with success/failure callbacks where the interface is asynchronous.
4. Keep a fallback path for a missing feature or a device that does not support it.

### Persistent storage

`system.storage` stores small key/value strings. Store JSON when the application has more than one value:

```json
{
  "features": [
    { "name": "system.storage" }
  ]
}
```

```js
import storage from "@system.storage"

storage.set({
  key: "match-state",
  value: JSON.stringify({ orange: 2, blue: 1 }),
  success() {
    console.log("state saved")
  },
  fail(data, code) {
    console.error("storage.set failed", code, data)
  }
})
```

Read the value on `onInit` or `onShow`, parse it, and fall back to a default state if the key is missing or malformed. The GLAM example keeps a draft score and a bounded history in one JSON value. It writes the draft after each score change and writes the completed match after saving.

The official API is [Data Storage](https://iot.mi.com/vela/quickapp/en/features/data/storage.html). Use [File Storage](https://iot.mi.com/vela/quickapp/en/features/data/file.html) for larger structured files, not for a small score object.

### Vibration

Declare and import the vibrator:

```json
{ "name": "system.vibrator" }
```

```js
import vibrator from "@system.vibrator"

try {
  vibrator.vibrate({ mode: "short" })
} catch (error) {
  console.error("vibration unavailable", error)
}
```

The official support table lists Xiaomi Band 10 for `vibrate`. The emulator can expose the interface and log the call, but it cannot reproduce the physical sensation of the band motor. The full [Vibration API reference](https://iot.mi.com/vela/quickapp/en/features/system/vibrator.html) distinguishes `vibrate` from the longer-running `start` and `stop` APIs.

### Routing and prompts

Declare `system.router` and use registered paths:

```js
import router from "@system.router"

router.push({ uri: "/pages/history" })
router.back()
```

Use `system.prompt` for a short confirmation or toast, but do not use a toast as the only error channel for a failed write. Xiaomi's [interaction guide](https://iot.mi.com/vela/quickapp/en/guide/start/add-interactivity.html) shows feature declaration and page navigation.

### More interfaces

The [interface index](https://iot.mi.com/vela/quickapp/en/features/) lists network, file, device, sensor, media, and system capabilities. Check the product support table for each interface before building a feature into a real app. A feature can exist in the emulator and still behave differently on a particular band firmware.

## 8. Build and package the application

From the project directory:

```bash
npm install
npm run build
```

The toolkit creates intermediate files in `build/` and the final debug package in `dist/`, with a name similar to:

```text
dist/com.example.myvelaapp.debug.1.0.0.rpk
```

An `.rpk` contains the compiled application resources and metadata expected by the Vela runtime. It is not a general Android APK. You can inspect a package without changing it:

```bash
unzip -l dist/*.rpk
```

Do not edit the generated archive by hand. Change the source and rebuild. Xiaomi's [development and packaging guide](https://iot.mi.com/vela/quickapp/en/guide/start/use-ide.html) describes the `dist/` and `build/` outputs and the difference between development and production packaging.

### Debug and release packages

Use the debug package while iterating in the emulator and during local development. For a release package, create a `sign/` directory containing:

```text
sign/
  private.pem
  certificate.pem
```

Generate a key pair only when you understand the security consequence. Keep `private.pem` out of Git, backups shared with others, and issue trackers. Xiaomi's documented OpenSSL command is:

```bash
openssl req -newkey rsa:2048 -nodes \
  -keyout private.pem \
  -x509 -days 3650 \
  -out certificate.pem
```

Move the two files into `sign/`, then run the toolkit's release command or use **Publish** in AIoT-IDE. Keep the private key stable for an application identity; changing it can make an installed package fail signature checks.

## 9. The emulator: npm package, runtime, image, and device profile

The emulator has four separate pieces:

| Piece | Role |
|---|---|
| `aiot-toolkit` / `@aiot-toolkit/emulator` | JavaScript commands and controller APIs |
| Emulator runtime | QEMU/NuttX executable and host libraries |
| Vela system image | The firmware and built-in wearable services |
| VVD profile | Name, display size, density, shape, skin, and image selection |

`npm install` installs the first piece. It does not download the other three. AIoT-IDE's simulator onboarding or the CLI command below downloads the runtime and system-image archives into the user's local Vela SDK cache:

```bash
npx aiot initEmulatorEnv
```

The download can be hundreds of megabytes. It is normal for the command to spend time downloading and then decompressing archives.

### Create a Band 10-like device

Use a custom-resolution watch image for a 212 × 520 test profile. In AIoT-IDE, open simulator management, choose a custom device, set width `212`, height `520`, density `320`, shape `pill-shaped`, and device type `band`.

The official multi-screen guide explains why the image choice matters. A `vela-miwear-watch-5.0` image includes a fixed watch environment and is not the right image for arbitrary dimensions. The adaptable `vela-watch` image is the useful choice when the toolkit version provides it. The exact image list can change between toolkit versions, so inspect the choices offered by the installed version. See Xiaomi's [multi-screen emulator documentation](https://iot.mi.com/vela/quickapp/en/tools/debug/multi-screens.html) before choosing an image or adding a custom skin.

The Band 10 skin used during this project declared a 212 × 520 display and a capsule mask. Keep a custom skin under the SDK's `skins/user/<skin-name>` directory if you need a device frame. Do not put the user's SDK path in the repository; select it through the IDE or a generated local profile.

### CLI caveat observed with toolkit 2.0.5

The installed `aiot-toolkit 2.0.5` has two rough edges:

- the interactive `createVVD` validator can call its “does this name already exist?” lookup before the new profile exists and abort with `VVD directory ... not found`;
- `aiot start` waits about eight seconds for the app-start log line. A custom `vela-watch-5.0` instance can boot and install the package while that wrapper times out.

Treat those messages as toolkit limitations, not proof that the RPK failed. Use the IDE's device-management flow, a newer toolkit after checking its changelog, or start the emulator profile manually and use ADB to install and launch the app. The manual sequence is:

```bash
# Start the emulator from AIoT-IDE, or use the executable shown by the IDE.
# Then confirm that the emulator is an ADB device.
adb devices -l

# The following path is inside the emulator, not a host path.
adb -s emulator-5554 shell pm install <path-visible-to-the-emulator>/app.rpk
adb -s emulator-5554 shell am start <package-name>
```

The repository's `scripts/emu-deploy.sh` assumes that the emulator is already running. It builds the selected project, pushes the RPK, extracts it with the emulator's `vapp` runtime, and can request a gRPC screenshot. Read [deployment-emulator.md](deployment-emulator.md) for the script's flags.

### gRPC screenshots and input

The emulator exposes a gRPC controller, usually on port 8554. After `cd scripts && npm install`, use:

```bash
node scripts/emulator-grpc.js screenshot "${TMPDIR:-/tmp}/vela-screen.png"
node scripts/emulator-grpc.js click 160 170
node scripts/emulator-grpc.js swipe 106 470 106 250 300
node scripts/emulator-grpc.js status
```

Use `click` for Vela `onclick` handlers. In testing, the emulator responded more reliably to gRPC mouse events than to touch events. The coordinates are physical screen pixels. Do not multiply them by `screen_width / designWidth` when the emulator already reports the native 212 × 520 display; the framework applies the `designWidth` conversion inside the app's CSS.

The helper needs the emulator controller proto. It searches common AIoT-IDE extension directories. If it cannot find the proto, set `VELA_PROTO_DIR` or pass `--proto-dir` as described in the script help. The official [AIoT-IDE simulator guide](https://iot.mi.com/vela/quickapp/en/tools/debug/multi-screens.html) describes the supported simulator workflow and its performance difference from real hardware.

## 10. Deploy to a real band

The real-device path has a different shape from the emulator path:

```text
source project -> npm build -> RPK on phone -> Mi Fitness debug page -> band
```

The repository launches Mi Fitness's hidden third-party-app debug fragment with a small phone-side `.dex` helper. It then uses UI automation to enter the package name and open the Android file picker. You select the RPK yourself. Mi Fitness sends it to the paired band.

Run the helper from the repository root:

```bash
./scripts/deploy.sh --project <project-dir>
```

Useful options:

```bash
./scripts/deploy.sh --project <project-dir> --serial <phone-serial>
./scripts/deploy.sh --project <project-dir> --no-build
./scripts/deploy.sh --project <project-dir> --uninstall
```

The script also accepts `PHONE_SERIAL`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, and `PICKER_WAIT_SECONDS`. Run `./scripts/deploy.sh --help` after checking out the repository version you intend to use.

The script does not send a message or choose the file for you. It stops at the file picker so you can select the RPK and verify the final result in Mi Fitness. Xiaomi documents the same debug-page route in the [FAQ](https://iot.mi.com/vela/quickapp/en/guide/other/faq.html). The technical details of the fragment launcher live in [deployment-real-device.md](deployment-real-device.md).

### Manual phone checks

Use these commands to diagnose the phone side before running the helper:

```bash
adb devices -l
adb -s <phone-serial> shell pm list packages | grep xiaomi.wearable
adb -s <phone-serial> shell getprop ro.build.version.release
adb -s <phone-serial> logcat -c
adb -s <phone-serial> logcat -v time | grep -iE 'wearable|third|rpk|quickapp'
```

The band does not need to appear as a second Android device. The phone must show `device`, not `unauthorized` or `offline`.

### Why the app may not appear in “System / Sort apps”

An independently installed third-party RPK belongs to the third-party app area managed by Mi Fitness. It does not become a built-in system application and may not appear in the firmware's system-app sorting screen. That screen controls a different catalog. Check the third-party app list or the launcher entry instead.

## 11. Individual ADB and package commands

These commands are useful when a script hides the failing step.

### Phone discovery

```bash
adb devices -l
adb -s <phone-serial> shell getprop ro.product.model
adb -s <phone-serial> shell dumpsys activity activities | head -80
```

### Emulator discovery

```bash
adb devices -l
adb -s emulator-5554 shell uname -a
adb -s emulator-5554 shell ls /data/quickapp/app
```

### Build and inspect an RPK

```bash
cd <project-dir>
npm install
npm run build
unzip -l dist/*.rpk
```

### Install and launch on a running Vela 5 emulator

```bash
adb -s emulator-5554 shell pm install <rpk-visible-to-emulator>
adb -s emulator-5554 shell am start <package-name>
adb -s emulator-5554 shell am stop <package-name>
```

The exact RPK transfer command depends on the image and toolkit. The repository helper uses the Vela `vapp` flow documented in [deployment-emulator.md](deployment-emulator.md); the official `vela-watch-5.0` runtime also accepts the `pm install` and `am start` flow used by `aiot start`.

### Inspect emulator output

```bash
node scripts/emulator-grpc.js status
node scripts/emulator-grpc.js screenshot "${TMPDIR:-/tmp}/screen.png"
```

Use AIoT-IDE's output and debug panel for JavaScript logs. On real hardware, reproduce the problem and pull firmware logs through Mi Fitness as described in Xiaomi's [FAQ](https://iot.mi.com/vela/quickapp/en/guide/other/faq.html).

## 13. A complete repeatable workflow

Use this order for a new application:

1. Create the project with AIoT-IDE or copy the smallest valid structure.
2. Choose the target display and set `config.designWidth` to the design draft width.
3. Write one page with explicit dimensions and one interaction.
4. Declare each Vela feature in `manifest.json` before importing it.
5. Add storage and failure callbacks before relying on persistence.
6. Build a debug RPK with `npm run build`.
7. Start a matching emulator profile and deploy the RPK.
8. Test the first screen, every route, and one data round-trip. Capture a screenshot.
9. Repeat with long labels, empty data, a reload, and an unsupported feature path.
10. Test on the real band for fonts, touch behavior, vibration, performance, and persistence.
11. Increase `versionCode`, create a signed release package, and keep the private key outside Git.
12. Run `./scripts/deploy.sh --project <project-dir>` and select the RPK in the phone's file picker.

This order separates three questions that often get mixed together: “did the source compile?”, “did the runtime render it?”, and “did Mi Fitness deliver it to the band?” Each tool answers only one of them.

The sequence follows Xiaomi's [AIoT-IDE workflow](https://iot.mi.com/vela/quickapp/en/guide/start/use-ide.html), [packaging workflow](https://iot.mi.com/vela/quickapp/en/tools/release/start.html), and [real-device installation flow](https://iot.mi.com/vela/quickapp/en/guide/other/faq.html).

## 14. Troubleshooting checklist

### `device is not connected`

Run `adb devices -l` and check the correct target. A phone, an emulator, and a band do not expose the same connection. For a real band, keep Mi Fitness paired and in range; the repository script needs the phone's ADB connection.

Use the [Android Debug Bridge reference](https://developer.android.com/tools/adb) for the device states and transport commands.

### The emulator is installed by npm, but no device exists

Install the runtime and image with `npx aiot initEmulatorEnv`, then create a VVD in AIoT-IDE. npm supplied the controller package; it did not create a device profile.

### The emulator shows a cropped application

Check the image type and the profile size. A fixed watch image can render its own 466-pixel environment through a 212-pixel viewport. Use a custom-resolution `vela-watch` profile for Band 10 layout work, and confirm the emulator log reports `212x520`.

### `aiot createVVD` says that a new name does not exist

This is the validation bug observed in `aiot-toolkit 2.0.5`. Create the profile through AIoT-IDE, upgrade after checking compatibility, or use the toolkit's `VvdManager` API from a local script. Do not delete an existing VVD to work around it.

### `aiot start` times out after the app installs

Check the emulator output for `InstallState_Finished`, `success 0`, and `Start App loop`. The toolkit wrapper waits for a short log window. Start the emulator separately, wait for ADB, then run the install and `am start` commands manually.

### The app installs but does not appear in a system-app sorter

Use the third-party app catalog in Mi Fitness. An RPK installed through the debug page is not a system application.

### Storage appears empty after a change

Check the key, JSON parsing, and asynchronous callbacks. Test the sequence “write → close → reopen → read” on the real band. Avoid writing a new object before the previous `storage.set` callback completes if multiple updates can race.

### Vibration works in logs but cannot be felt

That result is expected on a desktop emulator. Test `system.vibrator` on the physical band and keep a user setting to disable feedback.

### Text or touch differs from the emulator

Test the real firmware. Xiaomi notes that emulator performance differs from real devices. Fonts, anti-aliasing, touch coordinates, navigation gestures, and power behavior need a hardware pass.

## 15. Official references

- [Vela application overview](https://iot.mi.com/vela/quickapp/en/guide/)
- [Framework introduction](https://iot.mi.com/vela/quickapp/en/guide/framework/)
- [Create a project](https://iot.mi.com/vela/quickapp/en/tools/project/creat-project.html)
- [Project overview and directory structure](https://iot.mi.com/vela/quickapp/en/guide/start/project-overview.html)
- [`manifest.json` reference](https://iot.mi.com/vela/quickapp/en/guide/framework/manifest.html)
- [Script and lifecycle model](https://iot.mi.com/vela/quickapp/en/guide/framework/script/)
- [Page styling, box model, and design width](https://iot.mi.com/vela/quickapp/en/guide/framework/style/page-style-and-layout.html)
- [Responsive screen adaptation](https://iot.mi.com/vela/quickapp/en/guide/multi-screens/specs.html)
- [Multi-screen emulator and custom skins](https://iot.mi.com/vela/quickapp/en/tools/debug/multi-screens.html)
- [Data storage](https://iot.mi.com/vela/quickapp/en/features/data/storage.html)
- [File storage](https://iot.mi.com/vela/quickapp/en/features/data/file.html)
- [Vibration](https://iot.mi.com/vela/quickapp/en/features/system/vibrator.html)
- [Routing and interaction](https://iot.mi.com/vela/quickapp/en/guide/start/add-interactivity.html)
- [Packaging and release signing](https://iot.mi.com/vela/quickapp/en/tools/release/start.html)
- [Real-device FAQ and third-party installation](https://iot.mi.com/vela/quickapp/en/guide/other/faq.html)
- [AIoT-IDE development workflow](https://iot.mi.com/vela/quickapp/en/guide/start/use-ide.html)
- [This repository's original upstream](https://github.com/oryonatan/xiaomi-band-development)

The official links describe the platform contract. The emulator timeout, the `createVVD` validation failure, mouse-versus-touch behavior, and the Mi Band 10 212 × 520 profile were checked against the repository scripts and a working local Vela runtime; treat those observations as version-specific and re-check them after upgrading the toolkit.
