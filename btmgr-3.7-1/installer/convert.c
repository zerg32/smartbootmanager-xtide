/*
 * convert.c
 *
 * the program that convert binary files of SmartBtmgr into C source code
 *
 * Copyright (C) 2000, Suzhe, Lonius  See file COPYING for details.
*/

#include<stdio.h>

#define LOADER_SIZE 512
#define KNL_SIZE_OFF 10
#define THEME_SIZE_OFF 14

#ifndef LOADER_FILE
  #define LOADER_FILE "../release/loader.bin"
#endif

#ifndef MAIN_FILE
  #define MAIN_FILE "../release/main.bin"
#endif


#ifndef THEME_FR_FILE
  #define THEME_FR_FILE "../release/theme-fr"
#endif

#ifndef THEME_ES_FILE
  #define THEME_ES_FILE "../release/theme-es"
#endif

#ifndef THEME_CZ_FILE
  #define THEME_CZ_FILE "../release/theme-cz"
#endif

#ifndef THEME_RU_FILE
  #define THEME_RU_FILE "../release/theme-ru"
#endif

#ifndef THEME_HU_FILE
  #define THEME_HU_FILE "../release/theme-hu"
#endif

#ifndef THEME_DE_FILE
  #define THEME_DE_FILE "../release/theme-de"
#endif

#ifndef THEME_US_FILE
  #define THEME_US_FILE "../release/theme-us"
#endif

#ifndef THEME_ZH_FILE
  #define THEME_ZH_FILE "../release/theme-zh"
#endif

#ifndef THEME_PT_FILE
  #define THEME_PT_FILE "../release/theme-pt"
#endif


char *theme_symbols[]= {
	"theme_us_code",
	"theme_zh_code",
	"theme_de_code",
	"theme_hu_code",
	"theme_ru_code",
	"theme_cz_code",
	"theme_es_code",
	"theme_fr_code",
	"theme_pt_code",
	NULL
};

char *theme_headers[]= {
	"theme-us.h",
	"theme-zh.h",
	"theme-de.h",
	"theme-hu.h",
	"theme-ru.h",
	"theme-cz.h",
	"theme-es.h",
	"theme-fr.h",
	"theme-pt.h",
	NULL
};

char *theme_files[]= {
	THEME_US_FILE,
	THEME_ZH_FILE,
	THEME_DE_FILE,
	THEME_HU_FILE,
	THEME_RU_FILE,
	THEME_CZ_FILE,
	THEME_ES_FILE,
	THEME_FR_FILE,
	THEME_PT_FILE,
	NULL
};

unsigned char buf[32767];

void error(char *msg)
{
        fprintf(stderr,"\nError: %s",msg);
        exit (-1);
}

int main()
{
   int i, size, fn;
   FILE *fp;

   printf("\nConverting binary code into C header file...");

   printf("\nConverting %s\n", LOADER_FILE);
   if( (fp=fopen(LOADER_FILE,"rb"))==NULL )
       error("loader.bin not found!");
       
   fread(buf,sizeof(char),LOADER_SIZE,fp);
   fclose(fp);

   fp=fopen("loader.h","wt");
   fprintf(fp,"char loader_code[]=\n{\n");

   for(i=0;i<LOADER_SIZE;i++)
      {
      if((i%16)==0) fprintf(fp,"\n");
      fprintf(fp,"0x%02X,",buf[i]);
      }
   fprintf(fp,"\n};\n\n");
   fclose(fp);

   printf("\nConverting %s\n", MAIN_FILE);
   if( (fp=fopen(MAIN_FILE,"rb"))==NULL )
       error("main.bin not found!");
       
   fseek(fp, 0, SEEK_END);
   size = ftell(fp) + 1;
   rewind(fp);
   fread(buf,sizeof(char), size,fp);
   fclose(fp);
   fp=fopen("main.h","wt");
   fprintf(fp,"char main_code[]=\n{\n");

   size = * (short*)(buf + KNL_SIZE_OFF);

   for(i=0;i<size;i++)
      {
      if((i%16)==0) fprintf(fp,"\n");
      if((i%512)==0) fprintf(fp,"\n");
      fprintf(fp,"0x%02X,",buf[i]);
      }
   fprintf(fp,"\n};\n\n");
   fclose(fp);

   for(fn=0;theme_files[fn]!=NULL;fn++)
      {

      printf("\nConvert %s\n", theme_files[fn]);
      if( (fp=fopen(theme_files[fn],"rb"))==NULL )
          error(theme_files[fn]);

      fseek(fp, 0, SEEK_END);
      size = ftell(fp) + 1;
      rewind(fp);
      fread(buf,sizeof(char),size,fp);
      fclose(fp);
      if( (fp=fopen(theme_headers[fn],"wt"))==NULL )
          error(theme_headers[fn]);

      fprintf(fp,"char %s[]=\n{\n",theme_symbols[fn]);
      size = * (short*)(buf + THEME_SIZE_OFF);
      for(i=0;i<size;i++)
         {
         if((i%16)==0) fprintf(fp,"\n");
         if((i%512)==0) fprintf(fp,"\n");
         fprintf(fp,"0x%02X,",buf[i]);
         }
      fprintf(fp,"\n};\n\n");
      fclose(fp);
      }
   printf("\nConvertion complete.\n"); 
   return 0;
}
