# GitHub Publishing And XT-IDE Upgrade Plan

## Assumptions

- Proposed repository: `zerg32/smartbootmanager-xtide`
- Visibility: public
- License: `GPL-2.0-or-later`
- Vendor the complete upstream sources rather than downloading them during CI.
- Do not publish DOS, Windows, card backups, or full installed CF images.

## Step 1: Publish The Current Setup

### Preparation Status (September 2026)

- Completed: local Git repository initialized on `main`; vendored SBM and XT-IDE
  sources staged; proprietary operating-system media, card backups, build output,
  and captures ignored.
- Completed: `LICENSE`, `THIRD_PARTY.md`, `.gitattributes`, GitHub Actions, and
  a tested LBA 0-159 `boot-region.bin` target added.
- Completed: a clean export of the staged tree passes `make ci-boot-components
  boot-region`.
- Completed: pristine SBM and XT-IDE baseline commits tagged, followed by the
  current integration commit. The public repository is
  `https://github.com/zerg32/smartbootmanager-xtide`; `main` and both upstream
  tags are pushed.
- Completed: the initial GitHub Actions build passed and uploaded boot artifacts.
- Completed: the current rebuilt components were installed to `/dev/sde`, passed
  strict LBA 0-159 byte comparison, and started SBM on the physical 486.
- Remaining: optionally split the initial integration commit into narrower
  follow-up commits.

1. Preserve the currently working source state and record hashes for:
   - SBM 3.7.1 archive: `f17fa683705e4458d49537d8d122ad4d0b53de6e0f175e481209c7d79da1a03a`
   - XT-IDE baseline: Git commit `5961b06ba4d32c266b22e71c2b5fd429855efaf1`, equivalent to official SVN r619
   - Current generated SBM and XT-IDE binaries
2. Audit all changes against clean upstream sources:
   - Compare `btmgr-3.7-1/` against the SourceForge archive.
   - Compare `xtideuniversalbios/` against commit `5961b06b`.
   - Remove accidental line-ending-only changes from XT-IDE's `Initialize.asm` and `Main.asm`.
   - Retain the substantive `XTIDE_SBM_RETURN` change in `Int19h.asm`.
   - Confirm stock SBM auto-active behavior is restored.
3. Add a strict `.gitignore` before initializing Git:

   ```gitignore
   build/
   *.img
   *.iso
   *.rom
   *.bin
   *.zip
   *.7z
   *.ppm
   *.png
   *.log
   DOS622-Disk*.img
   ```

4. Explicitly verify these are excluded:
   - MS-DOS installation disks
   - Compaq DOS/Windows installation
   - Physical card backups
   - Partition backups
   - QEMU screenshots and logs
   - Generated 3.8/4 GiB images
   - Temporary debugging files
5. Before the first public commit, replace the current single staged snapshot
   with clean upstream/import commits in Git history. Completed in the initial
   repository history:
   - First commit: pristine SBM 3.7.1 from SourceForge.
   - Tag: `upstream/sbm-3.7.1`.
   - Second commit: pristine XT-IDE r619 snapshot.
   - Tag: `upstream/xtide-r619`.
   - Keep the existing directory names initially so the Makefile continues working.
6. Apply project modifications in focused commits:
   - SBM XT-IDE preload and CHS fallback
   - XT-IDE `XTIDE_SBM_RETURN` integration
   - SBM INT 13h wrapper stub
   - SBM page-zero UI handling
   - Loader-in-MBR image layout
   - Diagnostic MBR and stage 2
   - Image-building utilities
   - DOS migration and maintenance scripts
   - Documentation
7. Add provenance documentation in `THIRD_PARTY.md`:

   ```text
   Smart Boot Manager 3.7.1
   Source: https://sourceforge.net/projects/btmgr/
   SHA-256: f17fa683705e4458d49537d8d122ad4d0b53de6e0f175e481209c7d79da1a03a
   License: GPL-2.0-or-later

   XTIDE Universal BIOS
   Official upstream:
   https://www.xtideuniversalbios.org/svn/xtideuniversalbios/trunk
   Baseline revision: r619
   Equivalent Git commit:
   5961b06ba4d32c266b22e71c2b5fd429855efaf1
   License: GPL-2.0-or-later
   ```

8. Update documentation before publication:
   - State that the current XT-IDE baseline is official SVN r619.
   - Document the loader-in-MBR layout as deployed.
   - Document SBM's restored auto-active behavior.
   - Clearly distinguish historical shim, diagnostic, and final layouts.
   - Remove stale references saying the diagnostic layout is currently deployed.
   - State that proprietary operating-system files are not included.
9. Add a distributable `build/boot-region.bin` target. It should contain only LBA 0-143, or a larger fixed reservation if appropriate, without DOS/Windows data.
10. Add GitHub Actions that:
    - Install `nasm`, `perl`, `gcc`, and `make`.
    - Build the SBM loader and kernel.
    - Build XT-IDE.
    - Build the image utilities and diagnostic binaries.
    - Validate `SBML`, `SBMK`, `55 AA`, ROM size, and ROM checksum.
    - Validate partition-table constants and hidden-component LBAs.
    - Upload only small GPL-compatible boot binaries.
    - Do not upload sparse 4 GiB images.
11. Run local publication checks:

    ```sh
    make clean
    make
    make debug-images
    make final-image
    ```

12. Confirm that no excluded or proprietary files are staged:

    ```sh
    git status
    git diff --cached --stat
    git ls-files
    ```

13. Create `zerg32/smartbootmanager-xtide`, push the main branch and upstream tags, then verify the GitHub Actions build. Completed.
14. Tag the known-good release as `v0.1.0-xtide-r619`.
15. Describe that release as:

    ```text
    Hardware-tested on the target 486.
    SBM loader in MBR.
    SBM kernel at LBA 1.
    XT-IDE r619 at LBA 128.
    DOS/Windows partition at LBA 1008.
    ```

## Step 2: Upgrade XT-IDE

1. Create an `upgrade/xtide-r638` branch.
2. Export official XT-IDE SVN revision 638 from:

   ```text
   https://www.xtideuniversalbios.org/svn/xtideuniversalbios/trunk
   ```

3. Vendor the clean r638 tree and record:
   - SVN revision `638`
   - Export date
   - Source URL
   - Archive or tree checksum
4. Replace the r619 source without carrying forward accidental whitespace or line-ending changes.
5. Port `XTIDE_SBM_RETURN` into r638's `Int19h.asm`:
   - Preserve the normal upstream path under `%else`.
   - Run `Initialize_AndDetectDrives`.
   - Restore the temporary hotkey timer handler.
   - Use r638's optimized `USE_386` timer-vector restoration.
   - Restore the caller's stack.
   - Return to SBM using `IRET`.
6. Verify changed internal assumptions:
   - `BOOTVARS` layout
   - `RAMVARS` layout
   - POST-stack macros
   - Boot-menu stack macros
   - Interrupt-vector initialization
   - Timer-vector storage
   - Return-register expectations
7. Update the root Makefile for r638:
   - Remove `-DBIOS_SIZE=8192`.
   - Stop passing `8192` to `checksum.pl`.
   - Keep `XTIDE_SBM_RETURN`.
   - Review all module names for removals or changed dependencies.
   - Preserve the 386/AT/EBIOS/Win9x feature set.
8. Adapt image builders to variable-size XT-IDE ROMs:
   - Read the sector count from ROM byte 2.
   - Require the file size to equal the advertised size.
   - Accept 1-32 sectors.
   - Clear LBA 128-159 before writing the ROM.
   - Reject overlap with partitions or SBM data.
   - Stop requiring exactly 8,192 bytes.
9. Update disk-layout documentation if the new binary is not 8 KiB.
10. Add static validation:
    - ROM starts with `55 AA`.
    - ROM sector count is nonzero and no more than 32.
    - File length matches the header.
    - Additive checksum is zero.
    - SBM kernel and XT-IDE ranges do not overlap.
    - DOS still begins at LBA 1008.
11. Run QEMU regression tests:
    - Normal EDD path
    - Forced-CHS diagnostic path
    - SBM menu rendering
    - DOS boot
    - Windows 3.1 boot
    - Access beyond the motherboard's original BIOS limit
12. Compare r619 and r638 behavior:
    - Detected drive count
    - Reported disk geometry
    - EDD support
    - Conventional-memory consumption
    - Installed interrupt vectors
    - Partition visibility
    - Boot time
13. Prepare hardware rollback before deployment:

    ```sh
    dd if=/dev/sdX of=build/pre-r638-lba0-159.bin bs=512 count=160
    ```

14. Patch only the required low-LBA boot region for the first hardware test.
15. Test on the real 486:
    - SBM appears.
    - XT-IDE detects the CF card.
    - DOS boots.
    - Windows 3.1 boots.
    - All FAT16 partitions remain accessible.
    - Repeated warm and cold boots work.
    - No timer-related crash occurs.
    - Large-disk reads and writes work.
16. Restore the saved boot region immediately if any regression appears.
17. After successful hardware validation:
    - Update `THIRD_PARTY.md` to r638.
    - Update all generated-size and layout documentation.
    - Merge the upgrade branch.
    - Tag `v0.2.0-xtide-r638`.
    - Retain `v0.1.0-xtide-r619` as the known-good fallback.

The first GitHub release should remain identical to the proven hardware setup. The XT-IDE upgrade should be an isolated, reversible, and independently tested second phase.
