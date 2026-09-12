# Smart Boot Manager installer Makefile
#
# Copyright (c) Suzhe 2000
#

ifeq ($(CC),)
CC=		gcc
endif

ifeq ($(DEST_DIR),)
DEST_DIR=	../release
endif

ifeq ($(LOADER),)
LOADER=		$(DEST_DIR)/loader.bin
endif

ifeq ($(MAIN),)
MAIN=		$(DEST_DIR)/main.bin
endif           

ifeq ($(THEME_FR),)
THEME_FR=	$(DEST_DIR)/theme-fr
endif

ifeq ($(THEME_ES),)
THEME_ES=	$(DEST_DIR)/theme-es
endif

ifeq ($(THEME_CZ),)
THEME_CZ=	$(DEST_DIR)/theme-cz
endif

ifeq ($(THEME_HU),)
THEME_RU=	$(DEST_DIR)/theme-ru
endif

ifeq ($(THEME_HU),)
THEME_HU=	$(DEST_DIR)/theme-hu
endif

ifeq ($(THEME_DE),)
THEME_DE=	$(DEST_DIR)/theme-de
endif

ifeq ($(THEME_US),)
THEME_US=	$(DEST_DIR)/theme-us
endif

ifeq ($(THEME_ZH),)
THEME_ZH=	$(DEST_DIR)/theme-zh
endif

ifeq ($(THEME_PT),)
THEM_PT=	$(DEST_DIR)/theme-pt
endif

ifeq ($(TARGET_OS),linux)
CONVERT=	convert
SBMINST=	$(DEST_DIR)/sbminst
INST_TARGET=	$(BIN_DIR)/sbminst
INSTALL=	install -m 755
STRIP=		strip
endif

ifeq ($(TARGET_OS),dos)
CONVERT=	convert.exe
SBMINST=	$(DEST_DIR)/sbminst.exe
INST_TARGET=	$(BIN_DIR)/sbminst.exe
INSTALL=	cp
STRIP=		strip
endif

DATA_HEADERS=	main.h loader.h \
		theme-cz.h theme-ru.h \
		theme-hu.h theme-de.h \
		theme-us.h theme-zh.h \
		theme-es.h theme-fr.h \
		theme-pt.h

all: $(SBMINST)

$(SBMINST): sbminst.o $(DATA_HEADERS)
	$(CC) -o $@ $< -lucl

$(DATA_HEADERS): $(CONVERT) $(LOADER) $(MAIN) \
		$(THEME_CZ) $(THEME_RU) $(THEME_HU) \
		$(THEME_DE) $(THEME_US) $(THEME_ZH) \
		$(THEME_ES) $(THEME_FR) $(THEME_PT)
	@./$(CONVERT)

$(CONVERT): convert.o
	$(CC) -o $@ $<

convert.o: convert.c
	$(CC) -DLOADER_FILE=\"$(LOADER)\" -DMAIN_FILE=\"$(MAIN)\" \
	-DTHEME_CZ_FILE=\"$(THEME_CZ)\" \
	-DTHEME_RU_FILE=\"$(THEME_RU)\" \
	-DTHEME_HU_FILE=\"$(THEME_HU)\" \
	-DTHEME_DE_FILE=\"$(THEME_DE)\" \
	-DTHEME_US_FILE=\"$(THEME_US)\" \
	-DTHEME_ZH_FILE=\"$(THEME_ZH)\" \
	-DTHEME_ES_FILE=\"$(THEME_ES)\" \
	-DTHEME_FR_FILE=\"$(THEME_FR)\" \
	-DTHEME_PT_FILE=\"$(THEME_PT)\" \
	-c $<

sbminst.o: sbminst.c sbminst.h $(DATA_HEADERS)
	$(CC) -DTHEME_DIR=\"$(THEME_DIR)\" -c $<

install: all
	-@mkdir -p $(BIN_DIR)
	-@$(STRIP) $(SBMINST)
	-@$(INSTALL) $(SBMINST) ${INST_TARGET}

uninstall:
	-@rm -fr $(INST_TARGET) 

.PHONY: clean
clean:
	-@rm -f *~ *.bin core *.out *.o *.bak *.bkp loader.h main.h \
	theme-*.h convert convert.exe


