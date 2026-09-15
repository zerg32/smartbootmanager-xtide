@echo off
if exist XTIDE_Universal_BIOS\Inc\Revision.inc goto NoError1
echo Couldn't find Revision.inc! Make sure to commit from the working copy root!>con
pause<con>con
exit 1
:NoError1
if not exist CommitInProgress goto NoError2
echo Revision.inc has already been updated but not yet successfully committed!>con
pause<con>con
exit 0
:NoError2
set /p XUB_REV=<XTIDE_Universal_BIOS\Inc\Revision.inc
set /a XUB_REV+=1
echo|set /p=%XUB_REV%>XTIDE_Universal_BIOS\Inc\Revision.inc
echo.>CommitInProgress
exit 0