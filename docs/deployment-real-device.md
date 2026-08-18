# Real-device deployment reference

The real-device path sends an RPK through the paired phone. The band is not a normal Android ADB target, so the phone's serial is the one that matters.

The full explanation is in [`development-guide.md`](development-guide.md). This page records the helper's exact behavior and the commands needed to diagnose it.

## Preconditions

```bash
adb devices -l
adb -s <phone-serial> shell pm list packages | grep xiaomi.wearable
```

The phone must show `device`, Mi Fitness must be installed, and Mi Fitness must already be paired with the band. Use the international package `com.xiaomi.wearable`; the Chinese package has a different package name and internal UI.

The deployment helper also needs `javac`, `d8`, Python 3, and an Android SDK path. It accepts `ANDROID_HOME` or `ANDROID_SDK_ROOT`.

## Run the helper

```bash
./scripts/deploy.sh --project <project-dir>
```

Pass an explicit phone when more than one ADB target exists:

```bash
./scripts/deploy.sh \
  --project <project-dir> \
  --serial <phone-serial>
```

Useful options:

```text
--no-build              Use an existing RPK in the project's dist directory
--uninstall             Uninstall the package before starting the install flow
--serial <serial>       Select the phone ADB target
```

Environment variables:

```text
PHONE_SERIAL            Default phone serial
ANDROID_HOME            Android SDK directory
ANDROID_SDK_ROOT        Alternative Android SDK directory
PICKER_WAIT_SECONDS     File-picker timeout, default 180
```

The script checks the Mi Fitness UI with `uiautomator dump` and resource IDs rather than relying on fixed phone coordinates. It confirms the package name, opens the install page, checks that Android's file picker appeared, and waits for Mi Fitness to return. You still select the RPK in the picker yourself.

## What the launcher does

Mi Fitness contains an internal third-party application debug fragment. The helper:

1. Locates the installed Mi Fitness APK with `pm path`.
2. Compiles a small Java launcher into a DEX file.
3. Uses Android's `app_process` with a `PathClassLoader` to load Mi Fitness's internal classes.
4. Starts the internal third-party-app fragment as the shell user.
5. Uses the visible resource IDs to enter the package name and open the installer.
6. Leaves the file choice to you.

The launcher needs Mi Fitness's own class loader because its fragment-parameter class is an internal Parcelable. A normal third-party Android application cannot construct that object with the correct class loader.

## Manual diagnosis

```bash
adb -s <phone-serial> shell pm path com.xiaomi.wearable
adb -s <phone-serial> shell dumpsys activity activities | head -100
adb -s <phone-serial> shell uiautomator dump /sdcard/ui.xml
adb -s <phone-serial> exec-out cat /sdcard/ui.xml
adb -s <phone-serial> logcat -c
adb -s <phone-serial> logcat -v time | grep -iE 'wearable|third|rpk|quickapp'
```

If the hidden page is not visible, close the current Mi Fitness detail page and run the helper again. If ADB reports `unauthorized`, unlock the phone and accept the USB debugging dialog. If it reports `offline`, reconnect the cable or restart the wireless ADB connection.

## Installation result

The helper reports the status text returned by Mi Fitness. The success text in the tested international UI was `file sent successfully` in Spanish localization. A successful phone transfer still requires the band to be connected and enough storage to accept the package.

An independently installed RPK can appear in Mi Fitness's third-party app list or launcher without appearing in a firmware screen named “System / Sort apps”. That system sorter does not catalog third-party Quick Apps.

## Official references

- [Xiaomi FAQ: upload an RPK to a real device](https://iot.mi.com/vela/quickapp/en/guide/other/faq.html)
- [Manifest and versionCode](https://iot.mi.com/vela/quickapp/en/guide/framework/manifest.html)
- [Packaging and signing](https://iot.mi.com/vela/quickapp/en/tools/release/start.html)
- [Android Debug Bridge](https://developer.android.com/tools/adb)
