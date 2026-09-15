; Project name	:	XTIDE Univeral BIOS Configurator v2
; Description	:	Functions for loading and saving BIOS image file.

;
; XTIDE Universal BIOS and Associated Tools
; Copyright (C) 2009-2010 by Tomi Tilli, 2011-2013 by XTIDE Universal BIOS Team.
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 2 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
; Visit http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
;

; Section containing code
SECTION .text

;--------------------------------------------------------------------
; BiosFile_LoadFileFromDSSItoRamBuffer
;	Parameters:
;		DS:SI:	Name of file to open
;		SS:BP:	Menu handle
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX, DX, SI, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BiosFile_LoadFileFromDSSItoRamBuffer:
	mov		al, FILE_ACCESS.ReadOnly
	call	FileIO_OpenWithPathInDSSIandFileAccessInAL
	jc		SHORT .DisplayErrorMessage

	call	FileIO_GetFileSizeToDXAXusingHandleFromBXandResetFilePosition
	jc		SHORT .CloseUsingHandleFromBXandDisplayErrorMessage

	cmp		dx, MAX_EEPROM_SIZE_IN_BYTES >> 16
	jb		SHORT .FileNotTooBig
	ja		SHORT .FileTooBig
%if (MAX_EEPROM_SIZE_IN_BYTES & 0FFFFh) = 0
	test	ax, ax
	jnz		SHORT .FileTooBig
%else
	cmp		ax, MAX_EEPROM_SIZE_IN_BYTES & 0FFFFh
	ja		SHORT .FileTooBig
%endif
.FileNotTooBig:
	xchg	cx, ax

	call	.LoadFileWithNameInDSSIhandleInBXandSizeInDXCXtoRamBuffer
	jc		SHORT .CloseUsingHandleFromBXandDisplayErrorMessage

	mov		al, FLG_CFGVARS_FILELOADED
	call	Buffers_NewBiosWithSizeInDXCXandSourceInALhasBeenLoadedForConfiguration
	call	FileIO_CloseUsingHandleFromBX
	jmp		SHORT DisplayFileLoadedSuccessfully

.FileTooBig:
	call	DisplayFileTooBig
.CloseUsingHandleFromBXandDisplayErrorMessage:
	call	FileIO_CloseUsingHandleFromBX
.DisplayErrorMessage:
	jmp		SHORT DisplayFailedToLoadFile


;--------------------------------------------------------------------
; .LoadFileWithNameInDSSIhandleInBXandSizeInDXCXtoRamBuffer
;	Parameters:
;		BX:		File Handle
;		DX:CX:	File size
;		DS:SI:	File name
;	Returns:
;		CF:		Clear if successful
;				Set if error
;	Corrupts registers:
;		AX, SI, DI, DS
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
.LoadFileWithNameInDSSIhandleInBXandSizeInDXCXtoRamBuffer:
	push	es

	call	Buffers_GetFileBufferToESDI
	call	Registers_ExchangeDSSIwithESDI
	call	FileIO_ReadDXCXbytesToDSSIusingHandleFromBX
	jc		SHORT .ReturnError

	; Store filename to Cfgvars from ESDI
	push	cx

	call	Registers_CopyESDItoDSSI				; File name in DS:SI
	push	cs
	pop		es
	mov		di, g_cfgVars+CFGVARS.szOpenedFile
%ifdef CLD_NEEDED
	cld
%endif
	call	String_CopyDSSItoESDIandGetLengthToCX	; Returns with CF cleared

	pop		cx
ALIGN JUMP_ALIGN
.ReturnError:
	pop		es
	ret


;--------------------------------------------------------------------
; BiosFile_SaveUnsavedChanges
;	Parameters:
;		SS:BP:	Menu handle
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX, SI, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BiosFile_SaveUnsavedChanges:
	push	ds

	push	cs
	pop		ds
	mov		si, g_cfgVars+CFGVARS.szOpenedFile
	call	BiosFile_SaveRamBufferToFileInDSSI

	pop		ds
	ret


;--------------------------------------------------------------------
; BiosFile_SaveRamBufferToFileInDSSI
;	Parameters:
;		DS:SI:	Name of file to save
;		SS:BP:	Menu handle
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX, SI, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BiosFile_SaveRamBufferToFileInDSSI:
	push	es

	call	Buffers_GenerateChecksum
	call	Buffers_GetFileBufferToESDI
	call	EEPROM_GetXtideUniversalBiosSizeFromESDItoDXCX

	mov		al, FILE_ACCESS.WriteOnly
	call	FileIO_OpenWithPathInDSSIandFileAccessInAL
	jc		SHORT .DisplayErrorMessage

	push	ds
	call	Registers_CopyESDItoDSSI
	call	FileIO_WriteDXCXbytesFromDSSIusingHandleFromBX
	pop		ds
	pushf
	call	FileIO_CloseUsingHandleFromBX
	popf
	jc		SHORT .DisplayErrorMessage

	call	Buffers_ClearUnsavedChanges
	pop		es
	jmp		SHORT DisplayFileSavedSuccessfully

.DisplayErrorMessage:
	pop		es
	jmp		SHORT DisplayFailedToSaveFile


;--------------------------------------------------------------------
; DisplayFileLoadedSuccessfully
; DisplayFileSavedSuccessfully
; DisplayFailedToLoadFile
; DisplayFailedToSaveFile
; DisplayFileTooBig
;	Parameters:
;		SS:BP:	Menu handle
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, DX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
DisplayFileLoadedSuccessfully:
	mov		dx, g_szDlgMainLoadFile
	jmp		Dialogs_DisplayNotificationFromCSDX

ALIGN JUMP_ALIGN
DisplayFileSavedSuccessfully:
	mov		dx, g_szDlgMainSaveFile
	jmp		Dialogs_DisplayNotificationFromCSDX

DisplayFailedToLoadFile:
	mov		dx, g_szDlgMainLoadErr
	jmp		Dialogs_DisplayErrorFromCSDX

DisplayFailedToSaveFile:
	mov		dx, g_szDlgMainSaveErr
	jmp		Dialogs_DisplayErrorFromCSDX

DisplayFileTooBig:
	mov		dx, g_szDlgMainFileTooBig
	jmp		Dialogs_DisplayErrorFromCSDX
