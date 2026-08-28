# Theme Rotate

A bar widget plugin for [Omarchy](https://omarchy.org/) that randomizes or
auto-rotates your theme.

![Theme Rotate popup](preview.png)

## Features

- Bar icon (🔀) with a popup panel.
- **Random Theme Now** — manually shuffle to a random installed theme different from the current one.
- **Auto-rotate** on a schedule: Off / every 1h / 3h / 6h / 12h / Daily.
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

- **Random Theme Now** rotates immediately to a random theme.
- The **Auto-rotate** row picks how often it rotates on its own: Off, every
  1/3/6/12 hours, or Daily.

## How it works

A background timer inside the widget polls once a minute and compares the
current time against "last rotated + configured interval". When due, it runs
[`bin/rotate-random.sh`](bin/rotate-random.sh), which asks Omarchy for the
installed theme list and the current theme, picks a different one at random,
and applies it with `omarchy theme set`.

## License

MIT — see [LICENSE](LICENSE). No external dependencies beyond Omarchy itself
(the `omarchy` CLI) and standard `bash`.
