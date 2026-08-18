# Xiaomi Vela wearable development

This repository collects portable tooling and notes for building Xiaomi Vela JS Quick Apps, testing them in the Vela emulator, and sending an `.rpk` package to an international Xiaomi wearable through Mi Fitness.

The main guide is [`docs/development-guide.md`](docs/development-guide.md). It explains the complete workflow:

- creating a project from an AIoT-IDE template or from an empty directory;
- designing a capsule-screen app for Xiaomi Smart Band 10 at 212 × 520;
- declaring Vela features such as storage, vibration, prompts, and routing;
- building debug and release `.rpk` packages;
- setting up and using the emulator, including its custom-resolution image;
- deploying to a real device through Mi Fitness;
- using the scripts and individual ADB commands;
- diagnosing the failures that appeared during real emulator and band testing.

## Repository layout

```text
scripts/
  deploy.sh            Build and send an RPK through Mi Fitness on a phone
  emu-deploy.sh        Build and deploy an RPK to a running Vela emulator
  emulator-grpc.js     Screenshot and input helper for the emulator
docs/
  development-guide.md Complete portable guide
  deployment-emulator.md Emulator command reference
  deployment-real-device.md Real-device technical reference
examples/jokebook/      Complete example Vela JS application
```

## Quick start

```bash
git clone https://github.com/diegomarzaa/xiaomi-band-development.git
cd xiaomi-band-development

cd examples/jokebook
npm install
cd ../..

cd scripts
npm install
cd ..

./scripts/emu-deploy.sh --project examples/jokebook
```

The emulator must already be running and visible to ADB. For a real phone, connect the phone, pair the band in Mi Fitness, then run:

```bash
./scripts/deploy.sh --project examples/jokebook
```

Read the [complete development guide](docs/development-guide.md) before adapting the commands to another project or device.

## Upstream and license

The original CLI project is available at [oryonatan/xiaomi-band-development](https://github.com/oryonatan/xiaomi-band-development). This repository is Diego's fork. The project remains available under the [MIT license](LICENSE).
