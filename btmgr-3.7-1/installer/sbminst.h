#define MAX_SBM_SIZE  30000

#define LDR_HEAD  0
#define LDR_CYL   0
#define LDR_SECT  1

#define LDR_LBA   0

#define KNL_HEAD  0
#define KNL_CYL   0
#define KNL_SECT  2

#define KNL_LBA   1

#define MAJOR_FD        2	/* floppy major */
#define MAJOR_HD1       3	/* IDE HD major */
#define MAJOR_HD2       22      /* IDE HD major */
#define MAJOR_HD3       33      /* IDE HD major */
#define MAJOR_HD4       34      /* IDE HD major */
#define MAJOR_SD        8       /* SCSI HD major */

#define LDR_SIZE  446
#define SECTOR_SIZE 512
#define MAX_THEME_SIZE  10240

#define SBMT_MAGIC      0x544D4253	/* magic number of
					   Smart Boot Manager theme.
					 */
#define MAX_RECORD_NUM      32
#define SIZE_OF_BOOTRECORD  64

#define SIZE_OF_MBR         446

#define BR_GOOD_FLAG    0XAA55
#define BR_FLAG_OFF     0x01FE

#ifdef __linux__
#define BACKUP_MAGIC "SBMBAKUP_LINUX_3_7_1\x0a\x00"
#else
#define BACKUP_MAGIC "SBMBAKUP_MSDOS_3_7_1\x0a\x00"
#endif

#define KNLFLAG_FIRSTSCAN   0x01
#define KNLFLAG_SECURITY    0x02
#define KNLFLAG_NOINT13EXT  0x04
#define KNLFLAG_NOCDROM     0x08

#define KNLFLAG_REMLAST     0x10
#define KNLFLAG_COMPRESSED  0x80

typedef unsigned long dword;
typedef unsigned short word;
typedef unsigned char byte;

char about[] =
  "\nSmart Boot Manager 3.7.1 Installer Copyright (C) 2000 Suzhe, Lonius\n"
  "This is free software, you can redistribute it and/or modify it\n"
  "under the terms of the GNU General Public License version 2.\n\n"
  "This program comes with ABSOLUTELY NO WARRANTY!\n\n";

char usage_msg[] =
  " [-t theme] [-d drv_name] [-b backup_file] [-u backup_file] \n\n"
  " -t theme     select the theme to be used, in which the theme could be: \n"
  "                 us = English theme       de = German theme \n"
  "                 hu = Hungarian theme     zh = Chinese theme \n"
  "                 ru = Russian theme       cz = Czech theme \n"
  "                 es = Spanish theme       fr = French theme \n"
  "                 pt = Portuguese theme \n"
  "                 or a filename of user customized theme.\n\n"
#ifdef __linux__
  " -d drv_name  set the drive that you want to install Smart BootManager on.\n"
  "              /dev/fd0 is the first floppy driver, \n"
  "              /dev/hda is the first IDE harddisk driver.\n"
  "              /dev/sda is the first SCSI harddisk driver.\n\n"
#else
  " -d drv_id    set the drive that you want to install Smart BootManager on.\n"
  "              0   is the first floppy driver,\n"
  "              128 is the first hard driver.\n\n"
#endif
  " -c           disable CD-ROM booting feature.\n\n"
  " -b           backup the data that will be overwrited for future unistallation.\n\n"
  " -u           uninstall the boot loader, should be used alone.\n\n"
  " -y           do not ask any question or warning.\n";

struct fat12_header
{
/*=================== For floppy FAT12 filesystem ======================*/
  byte  bsOEM [8];		// OEM String
  word  bsSectSize;		// Bytes per sector
  byte  bsClustSize;		// Sectors per cluster
  word  bsRessect;		// # of reserved sectors
  byte  bsFatCnt;		// # of fat copies
  word  bsRootSize;		// size of root directory
  word  bsTotalSect;		// total # of sectors if < 32 meg
  byte  bsMedia;		// Media Descriptor
  word  bsFatSize;		// Size of each FAT
  word  bsTrackSect;		// Sectors per track
  word  bsHeadCnt;		// number of read-write heads
  dword bsHidenSect;		// number of hidden sectors
  dword bsHugeSect;		// if bsTotalSect is 0 this value is
				// the number of sectors
  byte  bsBootDrv;		// holds drive that the bs came from
  byte  bsReserv;		// not used for anything
  byte  bsBootSign;		// boot signature 29h
  dword bsVolID;		// Disk volume ID also used for temp
				// sector # / # sectors to load
  byte  bsVoLabel [11];		// Volume Label
  byte  bsFSType [8];		// File System type
/*====================================================================*/
}
__attribute__ ((packed));


struct sbml_header		// the header of smart boot manager
{				// loader.
  byte  jmp_cmd[3];

  struct fat12_header fat12;	// data for fat12 filesystem.
  word  reserved;

  dword magic;			// magic number.
  word  version;		// version.

  byte  kernel_sects1;		// size and address of kernel block 1
  dword kernel_addr1;		//
  byte  kernel_sects2;		// size and address of kernel block 2
  dword kernel_addr2;		//
  byte  kernel_sects3;		// size and address of kernel block 3
  dword kernel_addr3;		//
  byte  kernel_sects4;		// size and address of kernel block 4
  dword kernel_addr4;		//
  byte  kernel_sects5;		// size and address of kernel block 5
  dword kernel_addr5;		//
}
__attribute__ ((packed));


struct sbmk_header		// the header of smart boot manager
{				// kernel.
  dword jmp_cmd;		// jmp and nop command.
  dword magic;			// magic number.
  word  version;		// version.
  word  total_size;		// the size of kernel code.
  word  compress_addr;          // the address of compressed part
  byte  checksum;		// checksum value.
  byte  kernel_sectors;		// the total sectors that kernel
                                // and theme used.
  byte  kernel_drvid;		// driver id
  byte  kernel_sects1;		// size and address of kernel block 1
  dword kernel_addr1;
  byte  kernel_sects2;		// size and address of kernel block 2
  dword kernel_addr2;
  byte  kernel_sects3;		// size and address of kernel block 3
  dword kernel_addr3;
  byte  kernel_sects4;		// size and address of kernel block 4
  dword kernel_addr4;
  byte  kernel_sects5;		// size and address of kernel block 5
  dword kernel_addr5;

  word  reserved1;
  byte  kernel_flags;
  byte  delay_time;
  byte  direct_br;
  byte  default_record;
  dword root_password;

  byte  bootmenu_style;
  byte  reserved2;
  word  cdrom_ioport1;
  word  cdrom_ioport2;
  word  y2k_last_year;
  byte  y2k_last_month;
  byte  reserved3[3];

  byte  boot_records[ MAX_RECORD_NUM * SIZE_OF_BOOTRECORD ];
  byte  sbml_codes[ SIZE_OF_MBR ];
  byte  previous_mbr[ SECTOR_SIZE ];
}
__attribute__ ((packed));


struct sbmt_header		// the header of smart boot manager
{				// theme.
  dword magic;			// magic number = 'SBMT', 4 bytes.
  word reserved;
  byte lang[6];			// language of this theme, 6 bytes.
  word version;			// version, high byte is major version,
                                // low byte is minor version.
                                // should be equal to the version of
                                // Smart Boot Manager.
  word size;			// size of the theme (bytes).
}
__attribute__ ((packed));
