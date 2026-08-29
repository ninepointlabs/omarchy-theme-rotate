# Theme Rotate

A bar widget plugin for [Omarchy](https://omarchy.org/) that randomizes or
auto-rotates your theme, optionally following sunrise and sunset.

![Theme Rotate popup](preview.png)

## Features

- Bar icon (🔀) with a popup panel.
- **Random Theme Now** — manually shuffle to a random installed theme different from the current one.
- **Auto-rotate** on a schedule: Off / every 1h / 3h / 6h / 12h / Daily.
- **Follow the sun** — optional: pick a random light theme after sunrise
  and a random dark theme after sunset. Uses the same location as Omarchy
  weather (`omarchy weather location`, otherwise wttr.in by IP) and
  switches as soon as day becomes night (including after sleep/resume).
- Wall-clock based scheduling, so a laptop that sleeps through part of the
  interval still catches up correctly on resume instead of losing that time.
- Settings persist across shell restarts, stored in the widget's own
  `shell.json` entry — the same mechanism Omarchy's built-in widgets use.

## Requirements

- [Omarchy Linux](https://omarchy.org/) (Quickshell-based bar/shell).
- More than one installed theme for rotation to have something to rotate to
  (`omarchy theme list`).

## Install

```bash
omarchy plugin add https://github.com/ninepointlabs/omarchy-theme-rotate.git --enable
```

Or manually:

```bash
git clone https://github.com/ninepointlabs/omarchy-theme-rotate.git ~/.config/omarchy/plugins/tim.theme-rotate
omarchy plugin enable tim.theme-rotate
```

## Remove

```bash
omarchy plugin remove tim.theme-rotate
```

This disables the widget and deletes its plugin folder. It does not revert
your currently applied theme.

## Usage

Click the 🔀 icon in the bar:

- **Random Theme Now** rotates immediately to a random theme (or a random
  day/night theme when Follow the sun is on).
- The **Auto-rotate** row picks how often it rotates on its own: Off, every
  1/3/6/12 hours, or Daily.
- **Follow the sun** limits those picks to light themes during the day and
  dark themes at night. Theme light/dark comes from each theme's
  `colors.toml` `mode` field.

Set a weather location if you want sunrise/sunset for a specific place
instead of IP geolocation:

```bash
omarchy weather location --set "Tyler" 32.35,-95.30
```

## How it works

A background timer inside the widget polls once a minute and compares the
current time against "last rotated + configured interval". When due, it runs
[`bin/rotate-random.sh`](bin/rotate-random.sh), which asks Omarchy for the
installed theme list and the current theme, picks a different one at random,
and applies it with `omarchy theme set`.

When Follow the sun is on, [`bin/sun-status.sh`](bin/sun-status.sh) resolves
today's sunrise and sunset (cached for the day) and the rotator keeps the
current theme in the matching pool — switching as soon as the sun does.

## License

MIT — see [LICENSE](LICENSE). No external dependencies beyond Omarchy itself
(the `omarchy` CLI) and standard `bash`.
