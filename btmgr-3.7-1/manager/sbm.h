; sbm.h
;
; header file for main.asm and loader.asm
;
; Copyright (C) 2000, Suzhe. See file COPYING and CREDITS for details.
;

%define BR_GOOD_FLAG    0XAA55
%define BR_FLAG_OFF     0x01FE
%define PART_TBL_OFF    0x01BE

%define SECTOR_SIZE     0x200              ; size of a sector
%define CDSECTOR_SIZE   0x800              ; size of a CD-ROM sector

%define SBMK_MAGIC      0x4B4D4253         ; magic number of
                                           ; Smart Boot Manager kernel.
%define SBMK_VERSION    0x0307             ; version of kernel.
%define SBMT_MAGIC      0x544D4253         ; magic number of
                                           ; Smart Boot Manager theme.
%define SBMT_VERSION    0x0307             ; version of theme.
%define SBML_MAGIC      0x4C4D4253         ; magic number of
                                           ; Smart Boot Manager loader.
%define SBML_VERSION    0x0301             ; version of loader.

%define MAX_SBM_SIZE    30720             ; the max size of Smart Boot Manager

%define SIZE_OF_MBR     446                ; the size of master boot record

%define MAX_RECORD_NUM      32
%define MAX_FLOPPY_NUM      2
%define MAX_PASSWORD_LENGTH 16

%define BOOT_OFF        0x7C00             ; boot sector startup offset
%define BOOT_SEG	0x07C0
%define PART_OFF        0x0600             ; partition table offset
                                           ; Smart Boot Manager kernel startup
%define KERNEL_SEG      0x1000             ; Segment ( Off = 0 )
%define KNLBACKUP_SEG   0x2000             ; Backup Segment ( Off = 0 )

%define STACK_SEG       0x3000
%define STACK_SIZE      0x8000

%define SBM_SAVE_NBLKS  5

%ifndef STRUC_SBMK_HEADER
%define STRUC_SBMK_HEADER

struc struc_sbml_header
      .jmp_cmd     resb 3               ; cli and jmp command.

;=================== For floppy FAT12 filesystem ======================
      .bsOEM       resb 8               ; OEM String
      .bsSectSize  resw 1               ; Bytes per sector
      .bsClustSize resb 1               ; Sectors per cluster
      .bsRessect   resw 1               ; # of reserved sectors
      .bsFatCnt    resb 1               ; # of fat copies
      .bsRootSize  resw 1               ; size of root directory
      .bsTotalSect resw 1               ; total # of sectors if < 32 meg
      .bsMedia     resb 1               ; Media Descriptor
      .bsFatSize   resw 1               ; Size of each FAT
      .bsTrackSect resw 1               ; Sectors per track
      .bsHeadCnt   resw 1               ; number of read-write heads
      .bsHidenSect resd 1               ; number of hidden sectors
      .bsHugeSect  resd 1               ; if bsTotalSect is 0 this value is
                                        ; the number of sectors
      .bsBootDrv   resb 1               ; holds drive that the bs came from
      .bsReserv    resb 1               ; not used for anything
      .bsBootSign  resb 1               ; boot signature 29h
      .bsVolID     resd 1               ; Disk volume ID also used for temp
                                        ; sector # / # sectors to load
      .bsVoLabel   resb 11              ; Volume Label
      .bsFSType    resb 8               ; File System type

      .reserved    resb 2
;====================================================================

      .magic           resd 1           ; magic number.
      .version         resw 1           ; version.

      .kernel_sects1   resb 1           ; size and address of kernel block 1
      .kernel_addr1    resd 1           ;
      .kernel_sects2   resb 1           ; size and address of kernel block 2
      .kernel_addr2    resd 1           ;
      .kernel_sects3   resb 1           ; size and address of kernel block 3
      .kernel_addr3    resd 1           ;
      .kernel_sects4   resb 1           ; size and address of kernel block 4
      .kernel_addr4    resd 1           ;
      .kernel_sects5   resb 1           ; size and address of kernel block 5
      .kernel_addr5    resd 1           ;
endstruc

struc struc_sbmk_header
      .jmp_cmd         resd 1           ; jmp and nop command.
      .magic           resd 1           ; magic number.
      .version         resw 1           ; version.
      .total_size      resw 1           ; the size of kernel code.
      .compress_addr   resw 1           ; the address of compressed part
      .checksum        resb 1           ; checksum value.
      .kernel_sectors  resb 1           ;
      .kernel_drvid    resb 1           ;
      .kernel_sects1   resb 1           ; block map for SBMK
      .kernel_addr1    resd 1           ;
      .kernel_sects2   resb 1           ; only four blocks are allowed.
      .kernel_addr2    resd 1           ;
      .kernel_sects3   resb 1           ;
      .kernel_addr3    resd 1           ;
      .kernel_sects4   resb 1           ;
      .kernel_addr4    resd 1           ;
      .kernel_sects5   resb 1           ;
      .kernel_addr5    resd 1           ;
      .reserved1       resw 1           ;
      .kernel_flags    resb 1           ; kernel flags. 
      .delay_time      resb 1           ; delay time ( seconds )
      .direct_br       resb 1           ; >= MAX_RECORD_NUM means no
                                        ; direct boot.
      .default_record  resb 1           ; the record number will
                                        ; be booted after the
                                        ; delay time is up or ESC
                                        ; key is pressed.
      .root_password   resd 1           ; root password.

      .bootmenu_style  resb 2
      .cdrom_ioports   resw 2
      .y2k_last_year   resw 1
      .y2k_last_month  resb 1
      .reserved2       resb 3

; buffer to store boot records
      .boot_records    resb MAX_RECORD_NUM * SIZE_OF_BOOTRECORD
      .sbml_codes      resb SIZE_OF_MBR
      .previous_mbr    resb SECTOR_SIZE
endstruc

struc struc_sbmt_header
      .magic           resd 1           ; magic number.
      .reserved        resw 1           ;
      .lang            resb 6           ; language info.
      .version         resw 1           ; theme version.
      .size            resw 1           ; theme size.
endstruc


%endif

