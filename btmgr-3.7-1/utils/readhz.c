#include<stdio.h>
#include<string.h>

struct hz_info
{
    unsigned int  count;
    unsigned char qu;
    unsigned char wei;
    unsigned char asc1;
    unsigned char asc2;
    unsigned char dat[32];
};

static unsigned char cur_asc=1;
static unsigned int cur_hz=0;

static struct hz_info hz_buf[128];

int read_hz(char *buf,char qu, char wei,FILE *fp);
int insert_hz(unsigned char qu, unsigned char wei, char *dat);
int scan_hz(unsigned char *txt, FILE *fp);
int write_hztable(FILE *fp);
int write_strtable(unsigned char *txt, FILE *fp);

unsigned short get_hzasc(unsigned char qu, unsigned char wei);

int main(int argc, char *argv[])
{
    FILE *fpzk;
    char txt[32767];
    int i=0;
    
    memset(hz_buf, 0, sizeof(struct hz_info) * 128);

    fpzk=fopen("chs16.fon","rb");

    if( fpzk==NULL )
	{
        printf("\nFontLib Error!\n");
		return -1;
    }

    while( (txt[i] = fgetc(stdin)) != EOF ) i++;
    txt[i] = 0;

    printf("%s\n",txt);

    if( scan_hz(txt, fpzk) <0 ) return -1;
    if( write_hztable(stdout) <0 ) return -1;
    if( write_strtable(txt, stdout) <0 ) return -1;

    printf("\nNumber of hz = %d", cur_hz);

    fclose(fpzk);

    return 0;
}

int read_hz(char *buf,char qu, char wei,FILE *fp)
{   char temp[32];
    unsigned long seek=0;
    int i;
    seek= (unsigned long)((qu+95)*94L+wei+95)*32L;
    if(fseek(fp,seek,SEEK_SET)<0) return -1;
    if(fread(temp,32,1,fp)<1) return -1;
    for(i=0;i<16;i++)
    	{
    	buf[i]=temp[i*2];
        buf[i+16]=temp[i*2+1];
        }
    return 0;
}

int insert_hz(unsigned char qu, unsigned char wei, char *dat)
{
    int i;
    for (i=0; i<cur_hz; i++ )
       if(hz_buf[i].qu == qu && hz_buf[i].wei == wei)
       {
           hz_buf[i].count ++;
           return 0;
       }

    if( cur_hz >= 128 || cur_asc >= 256 ) return -1;
   
    hz_buf[cur_hz].qu   = qu;
    hz_buf[cur_hz].wei  = wei;
    hz_buf[cur_hz].asc1 = cur_asc;
    cur_asc ++;
    if( cur_asc == 0x0d ) cur_asc ++;
    if( cur_asc >= 0x1e && cur_asc < 128 ) cur_asc = 128;
    hz_buf[cur_hz].asc2 = cur_asc;
    cur_asc ++;
    if( cur_asc == 0x0d ) cur_asc ++;
    if( cur_asc >= 0x1e && cur_asc < 128 ) cur_asc = 128;

    memcpy(hz_buf[cur_hz].dat, dat, 32);

    hz_buf[cur_hz].count = 1;

    cur_hz ++;
    return 0;    
}

int scan_hz( unsigned char *txt, FILE *fp)
{
    char buf[32];
    while ( *txt != 0 )
    {
        if( *txt > 128 )
        {
            if( read_hz(buf, *txt, *(txt+1), fp) <0 ) return -1;
            if( insert_hz(*txt, *(txt+1), buf) <0 ) return -1;
            txt ++;
        }
        txt ++;
    }
    return 0;
}

int write_hztable(FILE *fp)
{
    int i, j;
    for(i=0; i<cur_hz; i++)
    {
        fprintf(fp,"\n  db %u      ;%c%c-1, count:%d",
	        (unsigned short)hz_buf[i].asc1 ,hz_buf[i].qu, hz_buf[i].wei, hz_buf[i].count);
        fprintf(fp,"\n  db ");
        for( j=0; j<15; j++ )
             fprintf(fp,"0x%02X,",hz_buf[i].dat[j]);
        fprintf(fp,"0x%02X",hz_buf[i].dat[15]);

        fprintf(fp,"\n  db %u      ;%c%c-2",
	        (unsigned short)hz_buf[i].asc2 ,hz_buf[i].qu, hz_buf[i].wei);
        fprintf(fp,"\n  db ");
        for( j = 16; j<31; j++ )
             fprintf(fp,"0x%02X,",hz_buf[i].dat[j]);
        fprintf(fp,"0x%02X",hz_buf[i].dat[31]);
        fprintf(fp,"\n");
    }
    return 0;
}

int write_strtable(unsigned char *txt, FILE *fp)
{ 
    unsigned short asc;
    
    while( *txt != 0 )
    {
        if( *txt < 128 ) fputc( (int)*txt, fp );
	else if( *txt >= 128 )
	{
	    asc = get_hzasc( *txt, *(txt+1) );
            fprintf(fp,"%u,%u", asc & 0xff, asc >> 8);
	    if(*(txt+2) != ',') fputc(',',fp);
	    txt ++;
	}
	txt ++;
    }
    return 0;
}

unsigned short get_hzasc(unsigned char qu, unsigned char wei)
{
    int i;
    for (i=0; i<cur_hz; i++)
        if( hz_buf[i].qu == qu && hz_buf[i].wei == wei )
            return ((unsigned short)hz_buf[i].asc1) | 
                   ((unsigned short)(hz_buf[i].asc2 << 8));
    return 0;
}
