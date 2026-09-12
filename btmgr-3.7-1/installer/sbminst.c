/*
 * sbminst.c
 *
 * the installation program for Smart BootManager
 * 
 * this program only supports Linux and DOS.
 *
 * Copyright (C) 2000, Suzhe, Lonius  See file COPYING for details.
*/



#if ( !defined( __linux__ ) && !defined( __DJGPP__ ) ) || !defined( __GNUC__ )
#error "This program only can be compiled by GNU C under Linux or DJGPP"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>
#include <ctype.h>

#ifdef COMPRESS_SBM
#include <ucl/ucl.h>
#endif

#ifdef __linux__

#include <linux/fs.h>
#include <linux/hdreg.h>
#include <linux/fd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <dirent.h>

#else

#include <bios.h>
#include <dos.h>

#endif

#include "loader.h"
#include "main.h"


#include "theme-fr.h"
#include "theme-es.h"
#include "theme-cz.h"
#include "theme-ru.h"
#include "theme-hu.h"
#include "theme-de.h"
#include "theme-us.h"
#include "theme-zh.h"
#include "theme-pt.h"

#include "sbminst.h"

char *theme_names[]= { "us", "zh", "de", "hu", "ru", "cz", "es", "fr", "pt", NULL };
char *theme_pointers[]= {
	theme_us_code,
	theme_zh_code,
	theme_de_code,
	theme_hu_code,
	theme_ru_code,
	theme_cz_code,
	theme_es_code,
	theme_fr_code,
	theme_pt_code,
	NULL
};

#ifndef THEME_DIR
  #ifdef __linux__
    #define THEME_DIR "/usr/share/btmgr"
  #else
    #define THEME_DIR ""
  #endif
#endif

#ifdef __linux__
char inst_dev[20];
#else
int inst_devid;
byte dev_sectors, dev_heads;
#endif

int knl_tsize;
FILE *bk_fp, *ui_fp;
byte buf_ldr[SECTOR_SIZE + 1], buf_knl[MAX_SBM_SIZE], buf_knl_ucl[MAX_SBM_SIZE];
byte buf_theme[MAX_THEME_SIZE];
byte *theme_code;

int always_yes;
int no_cdrom_booting;

struct sbml_header *p_loader;
struct sbmk_header *p_knl;
struct sbmt_header *p_theme;

void
init_settings ()
{
  knl_tsize = 0;		/* kernel part total size */
  bk_fp = NULL;
  ui_fp = NULL;
  theme_code = theme_us_code;
  always_yes = 0;
  no_cdrom_booting = 0;

#ifdef __linux__
  strcpy(inst_dev, "/dev/fd0");
#else
  inst_devid = 0;
#endif
  
}

void
die (char *fmt, ...)
{
  va_list ap;
  va_start (ap, fmt);
  vfprintf (stderr, fmt, ap);
  va_end (ap);
  fprintf (stderr, "\n");
  exit (-1);
}

static void
usage (char *name)
{
  char *here;

  here = strrchr (name, '/');
  if (here)
    name = here + 1;
  fprintf (stderr, "usage:\n %s %s", name, usage_msg);
  exit (0);
}

byte
calc_checksum (byte * knl, int size)
{
  byte checksum;
  int i;
  for (i = 0, checksum = 0; i < size; i++)
    checksum += (*knl++);
  checksum = -((char) checksum);
  return checksum;
}

void
grasp_params (int num, char *index[])
{
  int i, theme_size, fn;
  FILE *theme_fp;
  char *name;
  char tmpfn[128];

  i = num--;
  name = *index;
  if (!num || index[1][0] != '-')
    usage (name);

  while (num && (*(++index))[0] == '-')
    {
      if ((*index)[2])
	usage (name);
      num--;
      switch ((*index)[1])
	{
	case 't':
	  if (!num)
	    {
	      printf ("\nincomplete option %s\n", (*index));
	      usage (name);
	    }
	  num--, index++;

	  for( fn=0; theme_names[fn]!=NULL; fn++ )
	     if( strcasecmp ((*index), theme_names[fn]) == 0 )
		break;

	  if( theme_names[fn] != NULL )
	    theme_code = theme_pointers[fn];
	  else
	    {
              strncpy(tmpfn, *index, 128);
	      if ((theme_fp = fopen (tmpfn, "rb")) == NULL)
                {
		  strcpy(tmpfn, THEME_DIR);
                  strcat(tmpfn, "/");
                  strncat(tmpfn, *index, 127 - strlen(THEME_DIR));
	          if ((theme_fp = fopen (tmpfn, "rb")) == NULL)
		    die ("fopen %s: %s", (*index), strerror (errno));
		}
	      fseek (theme_fp, 0, SEEK_END);
	      theme_size = ftell (theme_fp);
	      rewind (theme_fp);

	      if (fread (buf_theme, (theme_size > 16384) ? 16384 : theme_size,
			 1, theme_fp) < 1)
		die ("fread %s: %s", (*index), strerror (errno));
	      theme_code = buf_theme;
	      fclose (theme_fp);
	    }
	  break;
	case 'd':
	  if (!num)
	    {
	      printf ("\nincomplete option %s\n", (*index));
	      usage (name);
	    }
	  num--, index++;

#ifdef __linux__
	  strncpy (inst_dev, (*index), 18);
	  inst_dev[19] = '\0';
#else
          inst_devid = atoi (*(index));
#endif

	  break;
	case 'b':
	  if (!num)
	    {
	      printf ("\nincomplete option %s\n", (*index));
	      usage (name);
	    }
	  num--, index++;
	  if ((bk_fp = fopen ((*index), "wb")) == NULL)
	    die ("fopen %s : %s", (*index), strerror (errno));
	  break;
	case 'u':
	  if (!num)
	    {
	      printf ("\nincomplete option %s\n", (*index));
	      usage (name);
	    }
	  num--, index++;
	  if (i > 3)
	    die ("uninstall option can only be used alone.");
	  if ((ui_fp = fopen ((*index), "rb")) == NULL)
	    die ("fopen %s : %s", (*index), strerror (errno));
	  break;
	case 'y':
	  always_yes = 1;
	  break;
	case 'c':
	  no_cdrom_booting = 1;
	  break;

	default:
	  usage (name);
	}
    }

#ifdef DEBUG
  printf ("end of grasping the params.\n");
#endif

}

#ifdef __linux__

int
open_blk_dev (char *dev)
{
  int devd, major, minor;
  struct stat st;

  if ((devd = open (dev, O_RDWR)) < 0)
    die ("open %s: %s", dev, strerror (errno));
  if (fstat (devd, &st) < 0)
    die ("stat %s: %s", dev, strerror (errno));
  if (!S_ISBLK (st.st_mode))
    die ("%s is not a block device!\n", dev);

/* Check device */
  major = MAJOR (st.st_rdev);
  minor = MINOR (st.st_rdev);

  if (major != MAJOR_FD && 
      major != MAJOR_HD1 && 
      major != MAJOR_HD2 &&
      major != MAJOR_HD3 &&
      major != MAJOR_HD4 &&
      major != MAJOR_SD)
    die ("device %s not support in this version.", dev);


  if ( ((major == MAJOR_HD1 || major == MAJOR_HD2|| 
       major == MAJOR_HD3 || major == MAJOR_HD4) && minor % 64 != 0) ||
       (major == MAJOR_SD && minor % 16 !=0 ) )
    die ("device %s is a partition!", dev);

#ifdef DEBUG
  printf ("open %s for R/W, press any key to continue...", dev);
  getchar ();
#endif
  return devd;
}

void
close_blk_dev (int dev_d, char *dev)
{
  sync ();
  if (close (dev_d) < 0)
    die ("close %s : %s", dev, strerror (errno));
}

#else

void
check_dev (int drv_id)
{
  byte tmp[10];
  if (biosdisk (8, drv_id, 0, 0, 1, 1, tmp))
    die ("Disk check error!");

  dev_sectors = tmp[0] & 0x3f;
  dev_heads = tmp[3];

  if (!dev_sectors || !dev_heads)
    die ("Disk check error!");
}

void
disk_io (int func, byte dev_id, int head, int cyl, int sect, char *buf,
         int sum)
{
  int i;
  for (i = 0; i < sum; i++)
    {
      if (biosdisk (func, dev_id, head, cyl, sect, 1, buf + i * 512))
        die ("Disk read/write error!");
      sect++;
      if (sect > dev_sectors)
        {
          sect = 1;
          if (head >= dev_heads)
            {
              head = 0;
              cyl++;
            }
          else
            head++;
        }
    }
}

#endif

void
proc_knl ()
{

  int devd, sect, head, cyl;
#ifdef COMPRESS_SBM
  int ucled_size, ucl_ret;
#endif

#ifdef __linux__
  devd = open_blk_dev (inst_dev);
#else
  check_dev (inst_devid);
#endif

  memcpy (buf_knl, main_code, p_knl->total_size);
  memcpy (buf_knl + p_knl->total_size, theme_code, p_theme->size);

  p_knl = (struct sbmk_header *) buf_knl;
  memcpy (p_knl->sbml_codes, loader_code, SIZE_OF_MBR);

#ifdef __linux__
  lseek( devd, 0, SEEK_SET );
  if( read( devd, p_knl->previous_mbr, SECTOR_SIZE ) != SECTOR_SIZE )
    die ("read %s: %s", inst_dev, strerror (errno));
#else
  disk_io(2, inst_devid, LDR_HEAD, LDR_CYL, LDR_SECT, buf_ldr, 1);
  memcpy (p_knl->previous_mbr, buf_ldr, SECTOR_SIZE);
#endif

#ifdef COMPRESS_SBM

#ifdef DEBUG
  printf("Compressing SBM ... \n");
  printf("Original size = %d\n", knl_tsize);
#endif

  memcpy (buf_knl_ucl, buf_knl, knl_tsize);
  if( (ucl_ret = ucl_nrv2b_99_compress(buf_knl_ucl + p_knl->compress_addr ,
	knl_tsize - p_knl->compress_addr ,
	buf_knl + p_knl->compress_addr ,
	&ucled_size,NULL,10,NULL,NULL)) != UCL_E_OK )
	die ("internal error - compression failed: %d\n", ucl_ret );
  knl_tsize = ucled_size + p_knl->compress_addr;

#ifdef DEBUG
  printf( "Compressed size = %d, start addr = %d\n", knl_tsize, p_knl->compress_addr );
#endif

  p_knl->kernel_flags |= KNLFLAG_COMPRESSED;
#endif

  if( no_cdrom_booting ) 
    p_knl->kernel_flags |= KNLFLAG_NOCDROM;

  p_knl->kernel_sectors = (knl_tsize + 511) / SECTOR_SIZE;
  p_knl->kernel_sects1 = p_knl->kernel_sectors;
  p_knl->kernel_addr1 = KNL_LBA;
  p_knl->kernel_sects2 = 0;
  p_knl->total_size = knl_tsize;

  p_knl->checksum = 0;
  p_knl->checksum = calc_checksum (buf_knl, knl_tsize);

  /* always begin at safe place */
#ifdef __linux__
  lseek (devd, SECTOR_SIZE * KNL_LBA, SEEK_SET);
  if (write (devd, buf_knl, knl_tsize) != knl_tsize)
    die ("write %s: %s", inst_dev, strerror (errno));

  close_blk_dev (devd, inst_dev);
#else
  disk_io (3, inst_devid, KNL_HEAD, KNL_CYL, KNL_SECT, buf_knl,
           p_knl->kernel_sectors);
#endif

#ifdef DEBUG
  printf ("Kernel part installed successfully.\n");
#endif
}

void
proc_ldr ()
{
  char *s;
  int devd;

#ifdef __linux__
  devd = open_blk_dev (inst_dev);
  lseek (devd, 0, SEEK_SET);
  if (read (devd, buf_ldr, SECTOR_SIZE) != SECTOR_SIZE )
    die ("read %s: %s", inst_dev, strerror (errno));
#else
  check_dev (inst_devid);
  disk_io(2, inst_devid, LDR_HEAD, LDR_CYL, LDR_SECT, buf_ldr, 1);
#endif

  memcpy (buf_ldr, loader_code, LDR_SIZE);
  * (word *) (buf_ldr + BR_FLAG_OFF) = BR_GOOD_FLAG;

  p_loader->kernel_sects1 = p_knl->kernel_sectors;
  p_loader->kernel_addr1 = KNL_LBA;
  p_loader->kernel_sects2 = 0;

#ifdef __linux__
  lseek (devd, 0, SEEK_SET);
  if (write (devd, buf_ldr, SECTOR_SIZE) != SECTOR_SIZE)
    die ("write %s: %s", inst_dev, strerror (errno));

  close_blk_dev (devd,inst_dev);
#else
  disk_io (3, inst_devid, LDR_HEAD, LDR_CYL, LDR_SECT, buf_ldr, 1);
#endif

#ifdef DEBUG
  printf ("Loader part installed successfully.\n");
#endif

}

void
backup ()
{
  int devd, ksectors;

  if (bk_fp == NULL)
    return;

  printf("Backing up the data...\n");

#ifdef __linux__

  devd = open_blk_dev (inst_dev);
  lseek (devd, 0, SEEK_SET);

  if (read (devd, buf_ldr, SECTOR_SIZE) != SECTOR_SIZE)
    die ("read %s: %s", inst_dev, strerror (errno));

  if (fwrite (BACKUP_MAGIC, strlen(BACKUP_MAGIC), 1, bk_fp) < 1 ||
      fwrite (inst_dev, 20, 1, bk_fp) < 1 ||
      fwrite (buf_ldr, SECTOR_SIZE, 1, bk_fp) < 1 )
    die ("fwrite backup file error");

  lseek (devd, SECTOR_SIZE * KNL_LBA, SEEK_SET);
  if (read (devd, buf_knl, knl_tsize) != knl_tsize)
    die ("read %s: %s", inst_dev, strerror (errno));

  if (fwrite (&knl_tsize, sizeof (knl_tsize), 1, bk_fp) < 1 ||
      fwrite (buf_knl, knl_tsize, 1, bk_fp) < 1 )
    die ("fwrite backup file error");

  close_blk_dev (devd,inst_dev);

#else

  check_dev (inst_devid);

  disk_io (2, inst_devid, LDR_HEAD, LDR_CYL, LDR_SECT, buf_ldr, 1);

  if (fwrite (BACKUP_MAGIC, strlen (BACKUP_MAGIC), 1, bk_fp) < 1 ||
      fwrite (&inst_devid, sizeof (inst_devid), 1, bk_fp) < 1 ||
      fwrite (buf_ldr, SECTOR_SIZE, 1, bk_fp) < 1)
    die ("write backup file error");

  ksectors = (knl_tsize + SECTOR_SIZE - 1) / SECTOR_SIZE;
  disk_io (2, inst_devid, KNL_HEAD, KNL_CYL, KNL_SECT, buf_knl, ksectors);

  if (fwrite (&ksectors, sizeof (ksectors), 1, bk_fp) < 1 ||
      fwrite (buf_knl, ksectors * SECTOR_SIZE, 1, bk_fp) < 1)
    die ("write backup file error");

#endif

  fclose (bk_fp);
}

void
unistall ()
{
  int ks;
  int devd;
  char buf[20];
  char sect_buf[SECTOR_SIZE+1];

  if (!always_yes)
    {
      printf ("Are you sure you want to uninstall Smart BootManager [y/n]?");
      fgets (buf, 19, stdin);

      if (buf[0] != 'y')
	die ("Abort uninstallation.");
    }

  if (fread (buf, strlen(BACKUP_MAGIC), 1, ui_fp) < 1)
    die ("fread backup file error");
  if (strcmp (buf, BACKUP_MAGIC) != 0)
    die ("Invalid backup file");

#ifdef __linux__

  if (fread (inst_dev, 20, 1, ui_fp) < 1 ||
      fread (buf_ldr, SECTOR_SIZE, 1, ui_fp) < 1 ||
      fread (&ks, sizeof (ks), 1, ui_fp) < 1 ||
      fread (buf_knl, ks, 1, ui_fp) < 1 )
    die ("fread backup file error");

  devd = open_blk_dev (inst_dev);
  lseek (devd, 0, SEEK_SET);
  if (write (devd, buf_ldr, SIZE_OF_MBR) != SIZE_OF_MBR)
    die ("write %s: %s", inst_dev, strerror (errno));

  lseek (devd, SECTOR_SIZE * KNL_LBA, SEEK_SET);
  if (write (devd, buf_knl, ks) != ks)
    die ("write %s: %s", inst_dev, strerror (errno));
  close_blk_dev (devd,inst_dev);

#else

  if (fread (&inst_devid, sizeof (inst_devid), 1, ui_fp) < 1 ||
      fread (buf_ldr, SECTOR_SIZE, 1, ui_fp) < 1 ||
      fread (&ks, sizeof (ks), 1, ui_fp) < 1 ||
      fread (buf_knl, ks * 512, 1, ui_fp) < 1)
    die ("fread backup file error");

  check_dev (inst_devid);

/* Retain current partition table */
  disk_io (2, inst_devid, LDR_HEAD, LDR_CYL, LDR_SECT, sect_buf, 1);
  memcpy(sect_buf, buf_ldr, SIZE_OF_MBR);
  *((word *)(sect_buf + BR_FLAG_OFF))=BR_GOOD_FLAG;
  disk_io (3, inst_devid, LDR_HEAD, LDR_CYL, LDR_SECT, sect_buf, 1);
  disk_io (3, inst_devid, KNL_HEAD, KNL_CYL, KNL_SECT, buf_knl, ks);

#endif

  fclose(ui_fp);
}

void
check_lilo ()
{
  int devd;
  char buf[512];

  /* searching lilo */

#ifdef __linux__

  devd = open_blk_dev (inst_dev);

  if (read (devd, buf, 10) != 10)
    die ("read %s: %s", inst_dev, strerror (errno));

  close_blk_dev (devd,inst_dev);

#else

  disk_io (2, inst_devid, LDR_HEAD, LDR_CYL, LDR_SECT, buf, 1);

#endif

  buf[10] = '\0';
  if (strcmp (buf + 6, "LILO") == 0)
    {
#ifdef __linux__
      printf ("It seems that LILO has been installed onto device %s\n"
              "Do you want to continue to install SmartBootManager [yes/no]?",
             inst_dev);
#else
      printf ("It seems that LILO has been installed onto drive %d\n"
              "Do you want to continue to install SmartBootManager [yes/no]?",
             inst_devid);
#endif

      fgets (buf, 5, stdin);
      if (strncmp (buf, "yes", 3) != 0)
    die ("Abort installation.");
    }
}

int
main (int argc, char *argv[])
{
  char input[20];

  printf (about);

#ifdef COMPRESS_SBM
  if (ucl_init() != UCL_E_OK)
      die("ucl_init() failed !!!\n");
#endif

  init_settings ();
  grasp_params (argc, argv);

  if (ui_fp != NULL)
    {
      unistall ();
      printf ("Uninstallation successful!");
      exit (0);
    }

  p_theme = (struct sbmt_header *) theme_code;
  p_knl = (struct sbmk_header *) main_code;
  p_loader = (struct sbml_header *) buf_ldr;

  if (p_theme->magic != SBMT_MAGIC)
    die ("Invalid theme file!");
  if (p_theme->version != p_knl->version)
    die ("Theme version mismatched!");
  if (p_theme->size > MAX_THEME_SIZE)
    die ("Theme file is too big!");

  knl_tsize = p_knl->total_size + p_theme->size;

  if (bk_fp != NULL)
    backup ();

  if (!always_yes)
    {
      check_lilo ();

#ifdef __linux__
      printf ("Are you sure you want to install Smart BootManager into drive %s [y/n]?",
	      inst_dev);
#else
      printf
        ("Are you sure you want to install Smart BootManager into drive %d [y/n]?",
         inst_devid);
#endif

      fgets (input, 19, stdin);

      if (input[0] != 'y')
	die ("Abort installation.");
    }

  proc_knl ();
  proc_ldr ();

  printf ("\nInstallation successful!\n");
  exit (0);
}
