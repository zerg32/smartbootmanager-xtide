#
# Smart BootManager kernel Makefile
#
# Copyright (c) Suzhe 2000
#

ifeq ($(ASM),)
ASM=		nasm
endif

INCLUDES=	hd_io.h ui.h knl.h sbm.h macros.h main.h atapi.h \
		helptool.h debug.h printf.h n2b_d8e.ash

THEMES=		themes/theme-de.asm themes/theme-us.asm themes/theme-zh.asm \
		themes/theme-cz.asm themes/theme-hu.asm themes/theme-ru.asm \
		themes/theme-es.asm themes/theme-fr.asm themes/theme-pt.asm

LOADER_DEPS=	loader.asm $(INCLUDES)
MAIN_DEPS=	main.asm main-cmds.asm main-utils.asm hd_io.asm ui.asm xtide_preload.asm \
		knl.asm utils.asm myint13h.asm edd30.asm tempdata.asm \
		edd30.bin $(INCLUDES) $(THEMES)

ifeq ($(DEST_DIR),)
DEST_DIR=	../release
endif

ifeq ($(LOADER),)
LOADER=		$(DEST_DIR)/loader.bin
endif

ifeq ($(MAIN),)
MAIN=		$(DEST_DIR)/main.bin
endif

EMULATE_FR=	$(DEST_DIR)/emu-fr.com
EMULATE_ES=	$(DEST_DIR)/emu-es.com
EMULATE_CZ=	$(DEST_DIR)/emu-cz.com
EMULATE_RU=	$(DEST_DIR)/emu-ru.com
EMULATE_HU=	$(DEST_DIR)/emu-hu.com
EMULATE_DE=	$(DEST_DIR)/emu-de.com
EMULATE_US=	$(DEST_DIR)/emu-us.com
EMULATE_ZH=	$(DEST_DIR)/emu-zh.com
EMULATE_PT=	$(DEST_DIR)/emu-pt.com

TARGETS=	$(LOADER) $(MAIN) \
		$(EMULATE_RU) $(EMULATE_HU) $(EMULATE_DE) \
		$(EMULATE_CZ) $(EMULATE_US) $(EMULATE_ZH) \
		$(EMULATE_ES) $(EMULATE_FR) $(EMULATE_PT)

all: $(TARGETS)


$(LOADER): $(LOADER_DEPS)
	$(ASM) -fbin -o $@ $<

$(MAIN): $(MAIN_DEPS)
	$(ASM) -fbin -o $@ $<

$(EMULATE_FR): $(MAIN_DEPS)
	$(ASM) -DEMULATE_PROG -DTHEME_FR -fbin -o $@ $<

$(EMULATE_ES): $(MAIN_DEPS)
	$(ASM) -DEMULATE_PROG -DTHEME_ES -fbin -o $@ $<

$(EMULATE_CZ): $(MAIN_DEPS)
	$(ASM) -DEMULATE_PROG -DTHEME_CZ -fbin -o $@ $<

$(EMULATE_RU): $(MAIN_DEPS)
	$(ASM) -DEMULATE_PROG -DTHEME_RU -fbin -o $@ $<

$(EMULATE_HU): $(MAIN_DEPS)
	$(ASM) -DEMULATE_PROG -DTHEME_HU -fbin -o $@ $<

$(EMULATE_DE): $(MAIN_DEPS)
	$(ASM) -DEMULATE_PROG -DTHEME_DE -fbin -o $@ $<

$(EMULATE_US): $(MAIN_DEPS)
	$(ASM) -DEMULATE_PROG -fbin -o $@ $<

$(EMULATE_ZH): $(MAIN_DEPS)
	$(ASM) -DEMULATE_PROG -DTHEME_ZH -fbin -o $@ $<

$(EMULATE_PT): $(MAIN_DEPS)
	$(ASM) -DEMULATE_PROG -DTHEME_PT -fbin -o $@ $<

edd30.bin: edd30.asm $(INCLUDES)
	$(ASM) -fbin -o $@ $< 

install: all
	@echo -e "\nNothing to be installed.\n"

.PHONY: clean uninstall

uninstall: 
	@echo -e "\nNothing to be uninstalled.\n"

clean:
	-@rm -f *~ core *.out *.o *.bak *.bkp *.bin 
