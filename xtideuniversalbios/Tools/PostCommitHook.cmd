@echo off
:TryAgain
if exist CommitInProgress goto NoError
if %6""=="" goto NotCalledFromTSVN
if %6=="%cd%" goto FileNotFound
cd %6
goto TryAgain
:NotCalledFromTSVN
if "%PreviousCD%"=="%cd%" goto FileNotFound
set PreviousCD=%cd%
cd..
goto TryAgain
:FileNotFound
echo PostCommitHook was called but no CommitInProgress file could be found!>con
echo Something is very wrong as this should not happen!>con
pause<con>con
exit 1
:NoError
del CommitInProgress
exit 0