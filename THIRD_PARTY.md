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
- Current upgrade branch: official SVN revision r638
- Retrieved: 2026-09-15 from the official revision URL
  `https://www.xtideuniversalbios.org/svn/xtideuniversalbios/!svn/bc/638/trunk/`
- Canonical r638 source-tree tar SHA-256: `31da76a8e41589ff19900d333f39f578aa96b2c8c8d02ebbc59b9234a8c729df`
- Known-good release baseline: r619, imported from Git snapshot
  `5961b06ba4d32c266b22e71c2b5fd429855efaf1`
- License: GPL-2.0-or-later

The complete source is vendored in `xtideuniversalbios/`. r638 reached SBM on
the target 486 on 2026-09-15, but has not completed DOS/Windows validation;
`v0.1.0-xtide-r619` remains the fallback. The build adds the
`XTIDE_SBM_RETURN` integration in
`XTIDE_Universal_BIOS/Src/Handlers/Int19h.asm`.

## Excluded Material

This repository intentionally excludes MS-DOS media, Compaq Windows software,
installed CF images, physical-card backups, and QEMU captures. Build artifacts
contain only GPL-compatible boot components; users must supply their own
licensed operating-system media.
