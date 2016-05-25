
; flat assembler interface for Win32
; Copyright (c) 1999-2015, Tomasz Grysztar.
; All rights reserved.

; Modified by Grom PE to remove timestamps from format headers
; and slightly reduced fasm.exe file size

	format	PE console

include 'sizeopt.inc'
include 'import.inc'

section '.text' code readable executable

start:

	mov	[con_handle],STD_OUTPUT_HANDLE
	mov	esi,_logo
	call	display_string

	call	get_params
	jc	information

	call	init_memory

	mov	esi,_memory_prefix
	call	display_string
	mov	eax,[memory_end]
	sub	eax,[memory_start]
	add	eax,[additional_memory_end]
	sub	eax,[additional_memory]
	shr	eax,10
	call	display_number
	mov	esi,_memory_suffix
	call	display_string

	call	[GetTickCount]
	mov	[start_time],eax

	call	preprocessor
	call	parser
	call	assembler
	call	formatter

	call	display_user_messages
	movzx	eax,[current_pass]
	inc	eax
	call	display_number
	mov	esi,_passes_suffix
	call	display_string
	call	[GetTickCount]
	sub	eax,[start_time]
	xor	edx,edx
	mov	ebx,100
	div	ebx
	or	eax,eax
	jz	display_bytes_count
	xor	edx,edx
	mov	ebx,10
	div	ebx
	push	edx
	call	display_number
	mov	dl,'.'
	call	display_character
	pop	eax
	call	display_number
	mov	esi,_seconds_suffix
	call	display_string
      display_bytes_count:
	mov	eax,[written_size]
	call	display_number
	mov	esi,_bytes_suffix
	call	display_string
	xor	al,al
	jmp	exit_program

information:
	mov	esi,_usage
	call	display_string
	mov	al,1
	jmp	exit_program

get_params:
	mov	[input_file],0
	mov	[output_file],0
	mov	[symbols_file],0
	mov	[memory_setting],0
	mov	[passes_limit],100
	call	[GetCommandLine]
	mov	[definitions_pointer],predefinitions
	mov	esi,eax
	mov	edi,params
    find_command_start:
	lodsb
	cmp	al,20h
	je	find_command_start
	cmp	al,22h
	je	skip_quoted_name
    skip_name:
	lodsb
	cmp	al,20h
	je	find_param
	or	al,al
	jz	all_params
	jmp	skip_name
    skip_quoted_name:
	lodsb
	cmp	al,22h
	je	find_param
	or	al,al
	jz	all_params
	jmp	skip_quoted_name
    find_param:
	lodsb
	cmp	al,20h
	je	find_param
	cmp	al,'-'
	je	option_param
	cmp	al,0Dh
	je	all_params
	or	al,al
	jz	all_params
	cmp	[input_file],0
	jne	get_output_file
	mov	[input_file],edi
	jmp	process_param
      get_output_file:
	cmp	[output_file],0
	jne	bad_params
	mov	[output_file],edi
    process_param:
	cmp	al,22h
	je	string_param
    copy_param:
	stosb
	lodsb
	cmp	al,20h
	je	param_end
	cmp	al,0Dh
	je	param_end
	or	al,al
	jz	param_end
	jmp	copy_param
    string_param:
	lodsb
	cmp	al,22h
	je	string_param_end
	cmp	al,0Dh
	je	param_end
	or	al,al
	jz	param_end
	stosb
	jmp	string_param
    option_param:
	lodsb
	cmp	al,'m'
	je	memory_option
	cmp	al,'M'
	je	memory_option
	cmp	al,'p'
	je	passes_option
	cmp	al,'P'
	je	passes_option
	cmp	al,'d'
	je	definition_option
	cmp	al,'D'
	je	definition_option
	cmp	al,'s'
	je	symbols_option
	cmp	al,'S'
	je	symbols_option
    bad_params:
	stc
	ret
    get_option_value:
	xor	eax,eax
	mov	edx,eax
    get_option_digit:
	lodsb
	cmp	al,20h
	je	option_value_ok
	cmp	al,0Dh
	je	option_value_ok
	or	al,al
	jz	option_value_ok
	sub	al,30h
	jc	invalid_option_value
	cmp	al,9
	ja	invalid_option_value
	imul	edx,10
	jo	invalid_option_value
	add	edx,eax
	jc	invalid_option_value
	jmp	get_option_digit
    option_value_ok:
	dec	esi
	clc
	ret
    invalid_option_value:
	stc
	ret
    memory_option:
	lodsb
	cmp	al,20h
	je	memory_option
	cmp	al,0Dh
	je	bad_params
	or	al,al
	jz	bad_params
	dec	esi
	call	get_option_value
	or	edx,edx
	jz	bad_params
	cmp	edx,1 shl (32-10)
	jae	bad_params
	mov	[memory_setting],edx
	jmp	find_param
    passes_option:
	lodsb
	cmp	al,20h
	je	passes_option
	cmp	al,0Dh
	je	bad_params
	or	al,al
	jz	bad_params
	dec	esi
	call	get_option_value
	or	edx,edx
	jz	bad_params
	cmp	edx,10000h
	ja	bad_params
	mov	[passes_limit],dx
	jmp	find_param
    definition_option:
	lodsb
	cmp	al,20h
	je	definition_option
	cmp	al,0Dh
	je	bad_params
	or	al,al
	jz	bad_params
	dec	esi
	push	edi
	mov	edi,[definitions_pointer]
	call	convert_definition_option
	mov	[definitions_pointer],edi
	pop	edi
	jc	bad_params
	jmp	find_param
    symbols_option:
	mov	[symbols_file],edi
      find_symbols_file_name:
	lodsb
	cmp	al,20h
	jne	process_param
	jmp	find_symbols_file_name
    param_end:
	dec	esi
    string_param_end:
	xor	al,al
	stosb
	jmp	find_param
    all_params:
	cmp	[input_file],0
	je	bad_params
	mov	eax,[definitions_pointer]
	mov	byte [eax],0
	mov	[initial_definitions],predefinitions
	clc
	ret
    convert_definition_option:
	mov	ecx,edi
	xor	al,al
	stosb
      copy_definition_name:
	lodsb
	cmp	al,'='
	je	copy_definition_value
	cmp	al,20h
	je	bad_definition_option
	cmp	al,0Dh
	je	bad_definition_option
	or	al,al
	jz	bad_definition_option
	stosb
	inc	byte [ecx]
	jnz	copy_definition_name
      bad_definition_option:
	stc
	ret
      copy_definition_value:
	lodsb
	cmp	al,20h
	je	definition_value_end
	cmp	al,0Dh
	je	definition_value_end
	or	al,al
	jz	definition_value_end
	cmp	al,'\'
	jne	definition_value_character
	cmp	byte [esi],20h
	jne	definition_value_character
	lodsb
      definition_value_character:
	stosb
	jmp	copy_definition_value
      definition_value_end:
	dec	esi
	xor	al,al
	stosb
	clc
	ret


include '..\source\win32\system.inc'

make_timestamp_dummy:
	xor eax,eax
	xor edx,edx
	ret

include '..\source\errors.inc'
include '..\source\symbdump.inc'
include '..\source\preproce.inc'
include '..\source\parser.inc'
include '..\source\exprpars.inc'
include '..\source\assemble.inc'
include '..\source\exprcalc.inc'
make_timestamp fix make_timestamp_dummy
include '..\source\formats.inc'
make_timestamp fix make_timestamp
include '..\source\x86_64.inc'
include '..\source\avx.inc'


section '.data' data readable writeable

include '..\source\tables.inc'
include '..\source\messages.inc'
include '..\source\version.inc'
VERSION_STRING equ VERSION_STRING,"-gpe (no timestamps)"

_copyright db 'Copyright (c) 1999-2015, Tomasz Grysztar',0Dh,0Ah,0

_logo db 'flat assembler  version ',VERSION_STRING,0
_usage db 0Dh,0Ah
       db 'usage: fasm <source> [output]',0Dh,0Ah
       db 'optional settings:',0Dh,0Ah
       db ' -m <limit>         set the limit in kilobytes for the available memory',0Dh,0Ah
       db ' -p <limit>         set the maximum allowed number of passes',0Dh,0Ah
       db ' -d <name>=<value>  define symbolic variable',0Dh,0Ah
       db ' -s <file>          dump symbolic information for debugging',0Dh,0Ah
       db 0
_memory_prefix db '  (',0
_memory_suffix db ' kilobytes memory)',0Dh,0Ah,0
_passes_suffix db ' passes, ',0
_seconds_suffix db ' seconds, ',0
_bytes_suffix db ' bytes.',0Dh,0Ah,0

align 4

label GetCommandLine dword at GetCommandLineA
label GetEnvironmentVariable dword at GetEnvironmentVariableA
label CreateFile dword at CreateFileA
import kernel32.dll, \
  CreateFileA, ReadFile, WriteFile, CloseHandle, SetFilePointer, \
  GetCommandLineA, GetEnvironmentVariableA, GetStdHandle, VirtualAlloc, \
  VirtualFree, GetTickCount, GetSystemTime, GlobalMemoryStatus, ExitProcess
importend

include '..\source\variable.inc'

con_handle dd ?
memory_setting dd ?
start_time dd ?
definitions_pointer dd ?
bytes_count dd ?
displayed_count dd ?
character db ?
last_displayed rb 2

params rb 1000h
options rb 1000h
predefinitions rb 1000h
buffer rb 4000h

stack 10000h

;section '.reloc' fixups data readable discardable
