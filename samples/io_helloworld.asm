BITS 32
  org 0x7c00
start:
  mov edx, 0x03f8
prompt:
  mov al, '>'
  out dx, al
input:
  in al, dx
  cmp al, 'h'
  je put_hello
  cmp al, 'w'
  je put_world
  cmp al, 'q'
  je fin
  jmp input
put_hello:
  mov esi, msg_hello
  call puts
  jmp prompt
put_world:
  mov esi, msg_world
  call puts
  jmp prompt
fin:
  jmp 0

puts:
  mov al, [esi]
  inc esi
  cmp al, 0
  je putsend
  out dx, al
  jmp puts
putsend:
  ret

msg_hello:
  db "hello", 0x0a, 0

msg_world:
  db "world", 0x0a, 0
