BITS 32
  org 0x7c00
start:
  mov eax, 0x00f1
  mov ebx, 0x0029
  call add_r
  jmp 0
add_r:
  mov ecx, eax
  add ecx, ebx
  ret