.486
.model flat,stdcall
option casemap:none

include windows.inc
include kernel32.inc
include user32.inc
include comctl32.inc
includelib kernel32.lib
includelib user32.lib
includelib comctl32.lib

.data
hinstance HINSTANCE ?
hLV dd ?
mainHWND HWND ?
.code

; this function zeros the buffer pointed by "dest" having the size of "dwSize" (that's obvious xD)
Clear proc uses edi dest:DWORD,dwSize:DWORD 
	
	mov edi,dest
	mov ecx,dwSize
	xor al,al
	rep stosb
	
	Ret
Clear EndP

; set the headers of listview 
SetHeaders proc uses edi

	local lvc : LVCOLUMN
	local index:DWORD
	
	invoke Clear,addr lvc,sizeof lvc
	
	.data
		szName db "Name",00
		szPID db "PID",00
	.code
	
	xor eax,eax
	mov index,eax
	
	push offset szName
	pop lvc.pszText
	mov lvc.lx,400
	mov lvc.imask,LVCF_WIDTH or LVCF_TEXT
	call @setheader
	
	push offset szPID
	pop lvc.pszText
	mov lvc.lx,50
	inc lvc.iSubItem
	inc index
	or lvc.imask,LVCF_SUBITEM
	call @setheader
	

	Ret
@setheader:
	invoke SendMessage,hLV,LVM_INSERTCOLUMN,index,addr lvc
	db 0C3h	

	
SetHeaders EndP

; add items to listview
SetItem proc uses edi lpszExeFile:DWORD,PID:DWORD

	local lvi: LV_ITEM
	local wstrOUT[10]:WCHAR
	
	invoke Clear,addr lvi,sizeof lvi
	
	push lpszExeFile
	pop lvi.pszText
	mov lvi.imask,LVIF_TEXT or LVIF_PARAM
	push PID
	pop lvi.lParam ; save the PID in lParam to avoid str2dw conversion
	invoke SendMessage,hLV,LVM_INSERTITEMW,0,addr lvi
	
	.Data
		format db "%",00,"X",00,00,00
	.code
	mov lvi.imask,LVIF_TEXT
	inc lvi.iSubItem
	lea ecx, wstrOUT
	push ecx
	pop lvi.pszText
	invoke wsprintfW,ecx,addr format,PID
	invoke SendMessage,hLV,LVM_SETITEMW,0,addr lvi
	
	ret
	
SetItem EndP

; get the list of running process
Listprocess proc

	local hSnapShot:HANDLE
	local lppe:PROCESSENTRY32W
	
	
	invoke Clear,addr lppe,sizeof lppe
	mov lppe.dwSize,sizeof lppe
	
	invoke SendMessage,hLV,LVM_DELETEALLITEMS,0,0
	invoke CreateToolhelp32Snapshot,TH32CS_SNAPPROCESS,-1
	.if eax!=-1
		mov hSnapShot,eax
		invoke Process32FirstW,hSnapShot,addr lppe
		.if eax			
			call @setitem
			.While 1
				invoke Process32NextW,hSnapShot,addr lppe
				.break .if !eax
				call @setitem
			.endw
		.endif
		invoke CloseHandle,hSnapShot	
	.endif	
	Ret
@setitem:
	invoke SetItem,addr lppe.szExeFile,lppe.th32ProcessID
	db 0c3h
Listprocess EndP

; terminate the slected process
Terminate proc uses edi esi Index:DWORD

	local lvi:LVITEM
	local hProcess:HANDLE,hSnap:HANDLE
	local lpte:THREADENTRY32
	
	invoke Clear,addr lvi,sizeof lvi
	mov lvi.imask,LVIF_PARAM
	mov lvi.iSubItem,1
	push Index
	pop lvi.iItem
	
	invoke SendMessage,hLV,LVM_GETITEMW,0,addr lvi ; read the item from listview
	mov esi,lvi.lParam ;; esi == process ID
	xor edi,edi
	dec edi ;; edi!=0 means operation failed, initialized with -1
	
	
	;; terminate porcess
	invoke OpenProcess,PROCESS_ALL_ACCESS,FALSE,esi
	.if eax!=-1
		mov hProcess,eax
		invoke TerminateProcess,eax,0
		.if eax
			xor edi,edi
		.endif	
		invoke CloseHandle,hProcess	
	.endif
	
	;; if failed try to terminate by thread (in some cases this works better that TerminateProcess)
	.if edi
		invoke CreateToolhelp32Snapshot,TH32CS_SNAPTHREAD,0 ;; snashot of all threads
		.if eax
			mov hSnap,eax
			invoke Clear,addr lpte,sizeof lpte
			mov lpte.dwSize,sizeof lpte
			invoke Thread32First,hSnap,addr lpte
			.if eax
				.while 1 ;; loop through all threads and compare their owner process ID to the one we have to terminate
					.if lpte.th32OwnerProcessID == esi
						invoke OpenThread,THREAD_TERMINATE,FALSE,lpte.th32ThreadID
						.if eax
							push eax
							invoke TerminateThread,eax,0
							.if eax
								xor edi,edi ;; at least one thread closed => mission success
							.endif
							call CloseHandle
						.endif
					.endif
					invoke Thread32Next,hSnap,addr lpte ;; next thread
					.break .if !eax
				.endw
			.endif
			invoke CloseHandle,hSnap
		.endif
	.endif
	
	.data
		szTerminated db "Terminated",00
		szFailed db "TerminateProcess failed",00
		szOK db "OK",00
	.code
	
	.if !edi
		mov eax,offset szTerminated
		mov ecx,offset szOK
		mov edx,MB_ICONINFORMATION
	.else
		mov eax,offset szFailed
		xor ecx,ecx
		mov edx,MB_ICONERROR
	.Endif
	invoke MessageBox,mainHWND,eax,ecx,edx	
	
	ret
Terminate EndP
main proc hwnd:HWND,umsg:UINT,wparam:WPARAM,lparam:LPARAM	
	
	.if hLV ; check that the dialog has been initalized (since this var is filled at WM_INITDIALOG)
		invoke GetAsyncKeyState,VK_F5 ; is F5 (refresh) button pressed
		and al,1
		.if al	
			invoke Listprocess
		.else
			invoke GetAsyncKeyState,VK_DELETE ; is delete (terminate) button pressed
			and al,1
			.if al
				invoke SendMessage,hLV,LVM_GETNEXTITEM,-1,LVNI_SELECTED ; check if an item is selected
				.if eax!=-1
					push eax ; push itemindex to "Terminate" proc
					.Data
						szDelete db "Terminate process?",00
						szDeleteCaption db "Confirmation",00
					.code
					invoke MessageBox,hwnd,addr szDelete,addr szDeleteCaption,MB_YESNO ; user confirmation
					.if eax==IDYES
						call Terminate ; terminate
						call Listprocess ; refresh list of process
					.endif
				.endif
			.endif
		.endif
	.endif
	
	invoke GetAsyncKeyState,VK_ESCAPE ; is escape (quit) pressed
	and al,1
	test al,al
	jne @close
	
	.if umsg == WM_INITDIALOG
		push hwnd
		pop mainHWND
		invoke LoadIcon,hinstance,1000 ; set window icon (actually there's no icon)
		invoke SendMessage,hwnd,WM_SETICON,ICON_BIG or ICON_SMALL,eax
		invoke GetDlgItem,hwnd,1002 ; retrieve the handle of listview (makes life easier)
		mov hLV,eax
		
		invoke SendMessage,eax,LVM_GETEXTENDEDLISTVIEWSTYLE,0,0 ; make listview fullrow select
		or eax,LVS_EX_FULLROWSELECT
		invoke SendMessage,hLV,LVM_SETEXTENDEDLISTVIEWSTYLE,0,eax 
		
		invoke SetHeaders ; setup the headers of the listview
		invoke Listprocess ; show process list
		
	.elseif umsg==WM_CLOSE
		@close:
		invoke EndDialog,hwnd,0 ; euh.. close :p
	.endif
	xor eax,eax
	Ret
main EndP
Start:
	invoke InitCommonControls
	invoke GetModuleHandle,0
	mov hinstance,eax
	invoke DialogBoxParam,hinstance,1001,0,addr main,0
	invoke ExitProcess,eax
End Start