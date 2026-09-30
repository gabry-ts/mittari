<div align="center">

<img src="docs/images/icon.png" width="128" alt="Mittari icon">

# Mittari

**Claude Code and Codex usage in the menu bar. Free and open source.**

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)](#requirements)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](Package.swift)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](https://www.gnu.org/licenses/gpl-3.0.html)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/statistics-dark.png">
  <img src="docs/screenshots/statistics-light.png" alt="Mittari statistics with tokens per hour and 5-hour windows" width="720">
</picture>

</div>

## Features

- 5-hour window: how far in you are, when it resets, what it cost
- Menu bar gauge with ring, percentage, reset time, tokens and cost
- Popover with week, today, this month, models, projects and Codex
- Statistics from 24 hours up to a year, by project and by model
- Notifications when the window crosses your thresholds
- Codex sessions, active time and token limits

## Install

```sh
brew install --cask gabry-ts/tap/mittari
```

Or download the latest `.dmg` from [Releases](https://github.com/gabry-ts/mittari/releases). Mittari updates itself automatically after that.

## Requirements

macOS 26 or later, Apple Silicon or Intel; reads Claude Code and/or Codex CLI logs on this Mac.

## Build from source

```sh
./scripts/build.sh   # build/Mittari.app
open build/Mittari.app
```

## Privacy

Mittari only reads your Claude Code and Codex logs, never writes to them, and has no network access, analytics or account.

## License

GNU General Public License v3.0. Copyright (C) 2026 Gabriele Partiti.
