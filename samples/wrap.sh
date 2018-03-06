#!/bin/sh
gcc -nostdlib -fno-asynchronous-unwind-tables -g -fno-stack-protector -fno-pie -m32 -c $1.c
nasm -f elf wrap.S
ld -m elf_i386 --entry=start --oformat=binary -Ttext 0x7c00 -o output.bin wrap.o $1.o