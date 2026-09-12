NASM ?= nasm

BUILD_DIR := build
SBM_DIR := btmgr-3.7-1/manager
XTIDE_DIR := xtideuniversalbios/XTIDE_Universal_BIOS

# Selectable MBR boot code. Use GENERIC_MBR=1 (default) for the plain
# active-partition MBR (no Syslinux handling); GENERIC_MBR=0 for the original
# Syslinux-derived MBR captured from the working CF card.
ifeq ($(GENERIC_MBR),1)
MBR_ASM := tools/generic_mbr.asm
MBR_BIN := $(BUILD_DIR)/mbr-generic.bin
else
MBR_ASM := tools/syslinux_mbr.asm
MBR_BIN := $(BUILD_DIR)/mbr-syslinux.bin
endif

XTIDE_DEFS := -DMODULE_STRINGS_COMPRESSED -DMODULE_HOTKEYS -DMODULE_8BIT_IDE -DMODULE_EBIOS -DMODULE_SERIAL -DMODULE_SERIAL_FLOPPY -DMODULE_POWER_MANAGEMENT -DNO_ATAID_VALIDATION -DCLD_NEEDED -DUSE_AT -DUSE_286 -DMODULE_IRQ -DMODULE_COMPATIBLE_TABLES -DUSE_386 -DMODULE_ADVANCED_ATA -DMODULE_WIN9X_CMOS_HACK -DXTIDE_SBM_RETURN -DBIOS_SIZE=8192
XTIDE_INCLUDES := $(foreach dir,$(XTIDE_DIR)/Inc $(XTIDE_DIR)/Inc/Controllers $(XTIDE_DIR)/Src $(XTIDE_DIR)/Src/Handlers $(XTIDE_DIR)/Src/Handlers/Int13h $(XTIDE_DIR)/Src/Handlers/Int13h/EBIOS $(XTIDE_DIR)/Src/Handlers/Int13h/Tools $(XTIDE_DIR)/Src/Handlers/Int19h $(XTIDE_DIR)/Src/Device $(XTIDE_DIR)/Src/Device/IDE $(XTIDE_DIR)/Src/Device/MemoryMappedIDE $(XTIDE_DIR)/Src/Device/Serial $(XTIDE_DIR)/Src/Initialization $(XTIDE_DIR)/Src/Initialization/AdvancedAta $(XTIDE_DIR)/Src/Menus $(XTIDE_DIR)/Src/Menus/BootMenu $(XTIDE_DIR)/Src/Libraries $(XTIDE_DIR)/Src/VariablesAndDPTs xtideuniversalbios/Assembly_Library/Inc xtideuniversalbios/Assembly_Library/Src xtideuniversalbios/Assembly_Library/Src/Display xtideuniversalbios/Assembly_Library/Src/File xtideuniversalbios/Assembly_Library/Src/Keyboard xtideuniversalbios/Assembly_Library/Src/Menu xtideuniversalbios/Assembly_Library/Src/Menu/Dialog xtideuniversalbios/Assembly_Library/Src/String xtideuniversalbios/Assembly_Library/Src/Time xtideuniversalbios/Assembly_Library/Src/Util xtideuniversalbios/Assembly_Library/Src/Serial,$(addprefix -I,$(dir)))

.PHONY: all clean qemu debug-images debug-binaries final-image boot-components boot-region ci-boot-components

all: $(BUILD_DIR)/cf-4gb.img

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/sbm-loader.bin: $(SBM_DIR)/loader.asm $(SBM_DIR)/hd_io.h $(SBM_DIR)/knl.h $(SBM_DIR)/sbm.h | $(BUILD_DIR)
	$(NASM) -f bin -I$(SBM_DIR)/ -o $@ $<

$(BUILD_DIR)/sbm-main.bin: $(SBM_DIR)/main.asm $(SBM_DIR)/xtide_preload.asm $(SBM_DIR)/myint13h_stub.asm $(SBM_DIR)/main-cmds.asm $(SBM_DIR)/main-utils.asm $(SBM_DIR)/hd_io.asm $(SBM_DIR)/ui.asm $(SBM_DIR)/knl.asm $(SBM_DIR)/utils.asm $(SBM_DIR)/tempdata.asm | $(BUILD_DIR)
	$(NASM) -f bin -I$(SBM_DIR)/ -DXTIDE_PRELOAD -DXTIDE_ROM_LBA=128 -DXTIDE_MAX_SECTORS=32 -DDISABLE_CDBOOT -o $@ $<

$(BUILD_DIR)/xtide-386.bin: $(XTIDE_DIR)/Src/Main.asm $(XTIDE_DIR)/Src/Handlers/Int19h.asm | $(BUILD_DIR)
	$(NASM) -f bin $(XTIDE_INCLUDES) -Worphan-labels -Ox $(XTIDE_DEFS) -o $@ $<
	perl xtideuniversalbios/Tools/checksum.pl $@ 8192

$(BUILD_DIR)/mbr-generic.bin: tools/generic_mbr.asm | $(BUILD_DIR)
	$(NASM) -f bin -o $@ $<

$(BUILD_DIR)/mbr-syslinux.bin: tools/syslinux_mbr.asm | $(BUILD_DIR)
	$(NASM) -f bin -o $@ $<

$(BUILD_DIR)/debug-mbr.bin: tools/debug_mbr.asm | $(BUILD_DIR)
	$(NASM) -f bin -o $@ $<

$(BUILD_DIR)/debug-mbr-chs.bin: tools/debug_mbr.asm | $(BUILD_DIR)
	$(NASM) -f bin -DFORCE_CHS -o $@ $<

$(BUILD_DIR)/debug-stage2.bin: tools/debug_stage2.asm | $(BUILD_DIR)
	$(NASM) -f bin -o $@ $<

$(BUILD_DIR)/debug-stage2-chs.bin: tools/debug_stage2.asm | $(BUILD_DIR)
	$(NASM) -f bin -DFORCE_CHS -o $@ $<

debug-binaries: $(BUILD_DIR)/debug-mbr.bin $(BUILD_DIR)/debug-mbr-chs.bin $(BUILD_DIR)/debug-stage2.bin $(BUILD_DIR)/debug-stage2-chs.bin

$(BUILD_DIR)/make_cf_image: tools/make_cf_image.c | $(BUILD_DIR)
	$(CC) -std=c99 -Wall -Wextra -Werror -O2 -o $@ $<

$(BUILD_DIR)/resize_cf_image: tools/resize_cf_image.c | $(BUILD_DIR)
	$(CC) -std=c99 -Wall -Wextra -Werror -O2 -o $@ $<

$(BUILD_DIR)/prepare_debug_image: tools/prepare_debug_image.c | $(BUILD_DIR)
	$(CC) -std=c99 -Wall -Wextra -Werror -O2 -o $@ $<

$(BUILD_DIR)/prepare_final_image: tools/prepare_final_image.c | $(BUILD_DIR)
	$(CC) -std=c99 -Wall -Wextra -Werror -O2 -o $@ $<

$(BUILD_DIR)/install_bootloader: tools/install_bootloader.c | $(BUILD_DIR)
	$(CC) -std=c99 -Wall -Wextra -Werror -O2 -o $@ $<

boot-components: $(BUILD_DIR)/sbm-loader.bin $(BUILD_DIR)/sbm-main.bin $(BUILD_DIR)/xtide-386.bin $(BUILD_DIR)/install_bootloader

$(BUILD_DIR)/boot-region.bin: $(BUILD_DIR)/sbm-loader.bin $(BUILD_DIR)/sbm-main.bin $(BUILD_DIR)/xtide-386.bin $(BUILD_DIR)/install_bootloader | $(BUILD_DIR)
	truncate -s 17M $(BUILD_DIR)/.boot-region-staging.img
	$(BUILD_DIR)/install_bootloader install $(BUILD_DIR)/.boot-region-staging.img 16 $(BUILD_DIR)/sbm-loader.bin $(BUILD_DIR)/sbm-main.bin $(BUILD_DIR)/xtide-386.bin
	dd if=$(BUILD_DIR)/.boot-region-staging.img of=$@ bs=512 count=160 status=none
	rm -f $(BUILD_DIR)/.boot-region-staging.img

boot-region: $(BUILD_DIR)/boot-region.bin

ci-boot-components: boot-components
	bash scripts/ci_boot_components.sh

$(BUILD_DIR)/cf-4gb.img: $(MBR_BIN) $(BUILD_DIR)/sbm-loader.bin $(BUILD_DIR)/sbm-main.bin $(BUILD_DIR)/xtide-386.bin $(BUILD_DIR)/make_cf_image
	$(BUILD_DIR)/make_cf_image $(MBR_BIN) $(BUILD_DIR)/sbm-loader.bin $(BUILD_DIR)/sbm-main.bin $(BUILD_DIR)/xtide-386.bin $@

qemu: $(BUILD_DIR)/cf-4gb.img
	qemu-system-i386 -cpu 486 -m 16M -drive if=ide,format=raw,file=$(BUILD_DIR)/cf-4gb.img -boot c

$(BUILD_DIR)/cf-debug-direct.img: $(BUILD_DIR)/cf-3.8gb-dos-1.5gb.img $(BUILD_DIR)/debug-mbr.bin $(BUILD_DIR)/debug-stage2.bin $(BUILD_DIR)/sbm-loader.bin $(BUILD_DIR)/sbm-main.bin $(BUILD_DIR)/xtide-386.bin $(BUILD_DIR)/prepare_debug_image
	cp --reflink=auto $< $@
	$(BUILD_DIR)/prepare_debug_image $(BUILD_DIR)/debug-mbr.bin $(BUILD_DIR)/debug-stage2.bin $(BUILD_DIR)/sbm-loader.bin $(BUILD_DIR)/sbm-main.bin $(BUILD_DIR)/xtide-386.bin $@

$(BUILD_DIR)/cf-debug-direct-chs.img: $(BUILD_DIR)/cf-3.8gb-dos-1.5gb.img $(BUILD_DIR)/debug-mbr-chs.bin $(BUILD_DIR)/debug-stage2-chs.bin $(BUILD_DIR)/sbm-loader.bin $(BUILD_DIR)/sbm-main.bin $(BUILD_DIR)/xtide-386.bin $(BUILD_DIR)/prepare_debug_image
	cp --reflink=auto $< $@
	$(BUILD_DIR)/prepare_debug_image $(BUILD_DIR)/debug-mbr-chs.bin $(BUILD_DIR)/debug-stage2-chs.bin $(BUILD_DIR)/sbm-loader.bin $(BUILD_DIR)/sbm-main.bin $(BUILD_DIR)/xtide-386.bin $@

debug-images: $(BUILD_DIR)/cf-debug-direct.img $(BUILD_DIR)/cf-debug-direct-chs.img

$(BUILD_DIR)/cf-final-direct.img: $(BUILD_DIR)/cf-debug-direct.img $(BUILD_DIR)/sbm-loader.bin $(BUILD_DIR)/prepare_final_image
	cp --reflink=auto $< $@
	$(BUILD_DIR)/prepare_final_image $(BUILD_DIR)/sbm-loader.bin $@

final-image: $(BUILD_DIR)/cf-final-direct.img

clean:
	rm -rf $(BUILD_DIR)
