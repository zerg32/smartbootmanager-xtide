# Third-Party Sources

## Smart Boot Manager

- Project: Smart Boot Manager 3.7.1
- Source: https://sourceforge.net/projects/btmgr/
- Release archive: `btmgr-3.7-1.tar.gz`
- SHA-256: `f17fa683705e4458d49537d8d122ad4d0b53de6e0f175e481209c7d79da1a03a`
- License: GPL-2.0-or-later

The complete source is vendored in `btmgr-3.7-1/`. Project-specific changes
are documented in `DEVELOPMENT.md`.

## XTIDE Universal BIOS

- Official upstream: https://www.xtideuniversalbios.org/svn/xtideuniversalbios/trunk
- Baseline: official SVN revision r619
- Imported Git snapshot: `5961b06ba4d32c266b22e71c2b5fd429855efaf1`
- License: GPL-2.0-or-later

The complete source is vendored in `xtideuniversalbios/`. The build adds the
`XTIDE_SBM_RETURN` integration in `XTIDE_Universal_BIOS/Src/Handlers/Int19h.asm`.

## Excluded Material

This repository intentionally excludes MS-DOS media, Compaq Windows software,
installed CF images, physical-card backups, and QEMU captures. Build artifacts
contain only GPL-compatible boot components; users must supply their own
licensed operating-system media.
