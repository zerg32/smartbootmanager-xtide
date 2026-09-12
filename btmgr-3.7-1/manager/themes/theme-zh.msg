; strings
; all strings are zero ending,
; use 0x0d to break string into multi-lines.
string:
; used in main window and boot menu.
.main_win_title     db  启,' ',动,' ',菜,' ',单,0
.menu_title         db  '    ',标,'  ',志,'    ',编,'  ',号,'  ',类,'  ',型,'   ',名,'  ',称,0

; window titles.
.about              db  'About',0
.error              db  错,'  ',误,0
.help               db  'Help',0
.info               db  信,'  ',息,0
.input              db  输,'  ',入,0

; used in input boxes.
.delay_time         db  延,'  ',时,': ',0
.name               db  名,'  ',称,': ',0
.new_root_passwd    db  新 
.root_passwd        db  管理口令,': ',0
.new_record_passwd  db  新 
.record_passwd      db  启动记录口令,': ',0
.retype_passwd      db  确认口令,':',0
.input_schedule     db  日程,' (hh:mm-hh:mm;days): ',0
.input_keystrokes   db  输入按键,'. ',按,' <Scroll Lock> ',键确认,0x0d
                    db  按,'  ',键,' = 0x',0
.key_count          db  '    No. ',0
.io_port            db  'I/O Base Ports (hex1,hex2): ',0

; used in record info box.
.drive_id           db     驱动器编号,': ',0
.part_id            db  '  ',分区编号,': ',0
.record_type        db  0x0d,'  ',记录类型,': ',0
.record_name        db  0x0d,'  ',记录名称,': ',0

.auto_active        db  0x0d,0x0d,'  ',自动激活,': ',0
.active             db  '  ',激活,': ',0
.auto_hide          db  0x0d,'  ',自动隐藏,': ',0
.hidden             db  '  ',隐藏,': ',0
.swap_drv           db  0x0d,交换驱动器,': ',0
.logical            db  '  ',逻辑,': ',0
.key_strokes        db  0x0d,0x0d,'    ',按,'  ',键,': ',0
.password           db  '  ',口令,': ',0
.schedule           db  0x0d,'    ',日,'  ',程,': ',0

.yes                db  'Yes',0
.no                 db  'No ',0

; copyright infomation, displayed at the top of the screen.
.copyright          db  ' Smart Boot Manager 3.7.0zh | Copyright (C) 2001 Suzhe',0

; hint message, displayed at the bottom of the screen.
.hint               db   '~F1~-Help  ~F2~-',保存,'  ~F3~-',名称,'  ~F4~-',激活,'  ~F5~-',隐藏,'  ~TAB~-',菜单,0

; about infomation.
.about_content     db '           Smart Boot Manager 3.7.0zh',0x0d
                   db ' Copyright (C) 2001 Suzhe <suzhe@gnuchina.org>',0x0d,0x0d
                   db ' This is free software, you can redistribute',0x0d
                   db ' it and/or modify it under the terms of the',0x0d
                   db '   GNU General Public License version 2.',0x0d,0x0d
                   db 'This program comes with ABSOLUTELY NO WARRANTY!',0

; help infomation.
.help_content:
        db '  F1 = Help        Ctrl+F1 = About',0x0d
        db '  F2 = ',保,'  ',存,'           F3 = ',名,'  ',称,0x0d
        db '  F4 = ',激,'  ',活,'           F5 = ',隐,'  ',藏,0x0d
        db ' TAB = ',菜,'  ',单,0x0d,0x0d
        db ' Please read the documentation for details.',0


; normal messages.
.changes_saved      db  保存,' OK.',0
.passwd_changed     db  口令设置, ' OK.',0
.ask_save_changes   db  保存设置,'(y/n)?',0

; error messages.
.wrong_passwd       db  口令错误,'!',0
.disk_error         db  驱动器错误,'! 0x',0
.mark_act_failed    db  激活错误,'!',0
.toggle_hid_failed  db  隐藏,'/',取消隐藏错误,'!',0
.no_system          db  'No Operating System!',0
.invalid_record     db  启动记录错误,'!',0
.invalid_schedule   db  日程错误,'!',0
.inst_confirm       db  确认安装,' Smart BootManager ',
                    db  到驱动器,0
.inst_ok            db  安装,' OK!',0
.inst_abort         db  取消安装,'.',0
.uninst_confirm     db  确认删除,' Smart BootManager?',0x0d,0
.uninst_ok          db  删除,' OK!',0x0d
                    db  'Computer will be restarted.',0
.uninst_abort       db  取消删除,'.',0
.confirm            db  按,' Y ',确认,'.',0
.no_sbml            db  'Smart Boot Manager Loader missing ',0x0d
                    db  'or version mismatch!',0
.invalid_ioports    db  'I/O Ports ',错误,'!',0

; command menu strings
; main menu
.main_mnu_title     db  'Main Menu',0
.main_mnu_help      db  'Help             ~F1~',0
.main_mnu_about     db  'About       ~Ctrl-F1~',0
.main_mnu_bootit    db  启,'  ',动,0
.main_mnu_bootprev  db  启动原有,' MBR',0
.main_mnu_quit      db  'Quit         ~Ctrl-Q~',0
.main_mnu_poweroff  db  'Power Off  ~Ctrl-F12~',0
.main_mnu_recordset db  启动记录设置,'     ->',0
.main_mnu_sysset    db  系统设置,'         ->',0
.main_mnu_save      db  保,'  ',存,'           ~F2~',0
.main_mnu_bar       db  '-------------------',0

; record settings menu
.record_mnu_title    db  启动记录设置,0
.record_mnu_info     db  信,'    ',息,'      ~/ or ?~',0
.record_mnu_name     db  名,'    ',称,'          ~F3~',0
.record_mnu_passwd   db  口,'    ',令,'          ~F9~',0
.record_mnu_schedule db  日,'    ',程,'      ~Ctrl-S~',0
.record_mnu_keys     db  按,'    ',键,'      ~Ctrl-K~',0
.record_mnu_act      db  激,'    ',活,'          ~F4~',0
.record_mnu_hide     db  隐,'    ',藏,'          ~F5~',0
.record_mnu_autoact  db  自动激活,'          ~F6~',0
.record_mnu_autohide db  自动隐藏,'          ~F7~',0
.record_mnu_swapdrv  db  交换驱动器,'    ~Ctrl-X~',0
.record_mnu_del      db  删,'    ',除,'      ~Ctrl-D~',0
.record_mnu_dup      db  复,'    ',制,'      ~Ctrl-P~',0
.record_mnu_moveup   db  上,'    ',移,'      ~Ctrl-U~',0
.record_mnu_movedown db  下,'    ',移,'      ~Ctrl-N~',0
.record_mnu_bar      db  '--------------------',0

; system setting menu
.sys_mnu_title       db  系统设置,0
.sys_mnu_rootpasswd  db  管理口令,'                ~F10~',0
.sys_mnu_admin       db  管理模式,'           ~Ctrl-F10~',0
.sys_mnu_security    db  安全模式,'            ~Alt-F10~',0
.sys_mnu_setdef      db  设置缺省记录,'             ~F8~',0
.sys_mnu_unsetdef    db  取消缺省记录,'       ~Shift-F8~',0
.sys_mnu_delay       db  设置延时,'             ~Ctrl-T~',0
.sys_mnu_bmstyle     db  设置启动菜单模式,'     ~Ctrl-F~',0
.sys_mnu_remlast     db  保存上次启动记录,'     ~Ctrl-L~',0
.sys_mnu_int13ext    db  'Toggle Extended Int 13H',0
.sys_mnu_rescanall   db  'Rescan All Drivers   ~Ctrl-I~',0
.sys_mnu_rescanpart  db  'Rescan All Harddisks ~Ctrl-H~',0
.sys_mnu_set_ioports db  设置,' CD-ROM I/O Ports',0
.sys_mnu_inst        db  安装,' Smart BootManager',0
.sys_mnu_uninst      db  删除,' Smart BootManager',0
.sys_mnu_bar         db  '---------------------------',0

.cdimg_mnu_title     db  'Choose a CD Image', 0
.cdimg_mnu_noemu     db  'No Emulation',0
.cdimg_mnu_120m      db  '1.2 M Diskette',0
.cdimg_mnu_144m      db  '1.44M Diskette',0
.cdimg_mnu_288m      db  '2.88M Diskette',0

.sunday              db 周日,0
.monday              db 周,' 1',0
.tuesday             db 周,' 2',0
.wednesday           db 周,' 3',0
.thursday            db 周,' 4',0
.friday              db 周,' 5',0
.saturday            db 周,' 6',0


; END OF THEME.
end_of_theme:
