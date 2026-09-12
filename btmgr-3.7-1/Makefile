# Smart Boot Manager Makefile
#
# Copyright (c) Suzhe 2000
#
# make			compile Smart Boot Manager
# make install		install Smart Boot Manager
# make uninstall	uninstall Smart Boot Manager
# make clean		delete unused files
#
# CONFIG:
#
# -DSHOW_DRV_NAME	Show driver name instead of driver number
# -DDISABLE_CDBOOT      Disable CD-ROM Boot
# -DSLOW_ATAPI_DEVICE	Use this option, if SBM cannot find your CD-ROM
# -DSTRICT_PART_CHECK   Uses strict partition check policy, which will 
#                       check the partition type and boot sector flag
#                       as well as the partition address.
# -DCOMPRESS_SBM        Compress SBM to reduce the code size
# -DY2K_BUGFIX          Use Y2k bugfix code for old BIOS
###########################################################################

CONFIG= -DSHOW_DRV_NAME -DSLOW_ATAPI_DEVICE -DCOMPRESS_SBM -DY2K_BUGFIX \
	-DSTRICT_PART_CHECK

.EXPORT_ALL_VARIABLES:

# change following macro to dos, if you want to compile sbm under dos
TARGET_OS=linux

ifeq ($(VERSION),)
  VERSION=3.7
endif

ifeq ($(TARGET_OS),linux)

  ifeq ($(PREFIX),)
    PREFIX=		/usr
  endif

BIN_DIR=	$(PREFIX)/sbin
DOC_DIR=	$(PREFIX)/share/doc/btmgr-$(VERSION)
INFO_DIR=	$(PREFIX)/info
THEME_DIR=	$(PREFIX)/share/btmgr

else
ifeq ($(TARGET_OS),dos)

PREFIX=		/btmgr
BIN_DIR=	$(PREFIX)
DOC_DIR=	$(PREFIX)/doc
INFO_DIR=	$(PREFIX)/info
THEME_DIR=	$(PREFIX)/theme

else

$(error Invalid TARGET OS!)

endif
endif

TOPDIR=		$(shell if [ "$$PWD" != "" ]; then echo $$PWD; else pwd; fi)
DEST_DIR=	$(TOPDIR)/release


COMMON_FLAGS=	$(CONFIG) -g

ASM=		nasm $(CONFIG)
CC=		gcc $(COMMON_FLAGS)

SUBDIRS=	manager manager/themes installer docs
#SUBDIRS=	manager manager/themes installer

LOADER=		$(DEST_DIR)/loader.bin
MAIN=		$(DEST_DIR)/main.bin
THEME_FR=	$(DEST_DIR)/theme-fr
THEME_ES=	$(DEST_DIR)/theme-es
THEME_CZ=	$(DEST_DIR)/theme-cz
THEME_RU=	$(DEST_DIR)/theme-ru
THEME_HU=	$(DEST_DIR)/theme-hu
THEME_DE=	$(DEST_DIR)/theme-de
THEME_US=	$(DEST_DIR)/theme-us
THEME_ZH=	$(DEST_DIR)/theme-zh
THEME_PT=	$(DEST_DIR)/theme-pt

#
# Rules
#
############################################################################
all:
	@echo -e "\nCompiling Smart Boot Manager\n"
	-@mkdir $(DEST_DIR)
	@rm -f errors.log
	@set -e; for i in $(SUBDIRS); do $(MAKE) -C $$i 2>&1|tee -a errors.log;done
	@rm -f errors.log

	@echo -e "\nCompilation complete.\n"

clean:
	@echo -e "\nCleaning up\n"
	@set -e; for i in $(SUBDIRS); do $(MAKE) clean -C $$i ;done
	@rm -fr $(DEST_DIR) *.bak core *~ *.bkp
	@echo -e "\nComplete.\n"

install: all
	-@mkdir -p $(PREFIX)
	@echo -e "\nInstalling\n"
	@set -e; for i in $(SUBDIRS); do $(MAKE) install -C $$i ;done
	@echo -e "\nComplete.\n"

uninstall:
	@echo -e "\nUnnstalling\n"
	@set -e; for i in $(SUBDIRS); do $(MAKE) uninstall -C $$i ;done
	@echo -e "\nComplete.\n"
