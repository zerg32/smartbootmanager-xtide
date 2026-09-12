#include<bios.h>
#include<stdio.h>

int main()
{
 int key;
 for(;;)
 {
  key = bioskey(0);
  printf("Key = 0x%x\n",key);
  if( key == 0x011b ) break;
 }
 return 0;
}

