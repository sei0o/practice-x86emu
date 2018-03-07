defmodule X86emu.Emulator do
  @behaviour Access

  defstruct registers: %{}, eflags: 0, memory: %{}, eip: 0, started: false

  # see: https://github.com/benjamintanweihao/chip8/blob/master/lib/chip8/io.ex
  defdelegate fetch(a, b), to: Map
  defdelegate get(a, b, c), to: Map
  defdelegate get_and_update(a, b, c), to: Map
  defdelegate pop(a, b), to: Map

  use Bitwise
  alias X86emu.ModRM
  
  def seek(emu, val), do: %{emu | eip: emu.eip + val}

  def get_code8(emu, offset \\ 0) do
    emu.memory[emu.eip + offset]
  end

  def get_code8_signed(emu, offset \\ 0) do
    <<ret :: integer-signed-8>> = <<get_code8(emu, offset) :: integer-unsigned-8>>
    ret
  end

  def get_code32(emu, offset \\ 0, byt \\ 3)
  def get_code32(emu, offset, 0), do: get_code8(emu, offset)
  def get_code32(emu, offset, byt) do
    get_code8(emu, offset + byt) <<< byt * 8 ||| get_code32(emu, offset, byt - 1)
  end

  def get_code32_signed(emu, offset \\ 0) do
    <<ret :: integer-signed-32>> = <<get_code32(emu, offset) :: integer-unsigned-32>>
    ret
  end

  # ? should we return size of modRM instead of seeking emulator directly? 
  def read_modrm(emu) do
    code = get_code8 emu
    modrm = %ModRM{
      mod: ((code &&& 0xc0) >>> 6),
      reg: ((code &&& 0x38) >>> 3),
      rm: code &&& 0x07
    }

    emu = emu |> seek(1)
    
    cond do
      modrm.mod != 3 and modrm.rm == 4 -> # sib
        {emu, %{modrm | sib: get_code8(emu)}}
      (modrm.mod == 0 and modrm.rm == 5) or modrm.mod == 2 -> # displacement 32
        {emu |> seek(4), %{modrm | disp: get_code32_signed(emu)}}
      modrm.mod == 1 -> # displacement 8
        {emu |> seek(1), %{modrm | disp: get_code8_signed(emu)}}
      true ->
        {emu, modrm}
    end

    # It's not possible to know whether "immediate value" is used or not from ModR/M; It depends on opcode.
    # Now emu's EIP points after ModR/M byte, SIB and the displacement
  end

  @doc "put value to address which ModR/M points"
  def set_rm32(emu, %ModRM{mod: 3, rm: reg_index}, value), do: set_register32(emu, reg_index, value)
  def set_rm32(emu, modrm, value) do
    addr = calc_mem_addr emu, modrm
    set_mem32 emu, addr, value
  end

  def get_rm32(emu, %ModRM{mod: 3, rm: reg_index}), do: get_register32(emu, reg_index)
  def get_rm32(emu, modrm) do
    addr = calc_mem_addr emu, modrm
    get_mem32 emu, addr
  end

  def set_rm8(emu, %ModRM{mod: 3, rm: reg_index}, value), do: set_register8(emu, register_name8(reg_index), value)
  def set_rm8(emu, modrm, value) do
    addr = calc_mem_addr emu, modrm
    set_mem8 emu, addr, value
  end

  def get_rm8(emu, %ModRM{mod: 3, rm: reg_index}), do: get_register8(emu, reg_index)
  def get_rm8(emu, modrm) do
    addr = calc_mem_addr emu, modrm
    get_mem8 emu, addr
  end

  def set_register32(emu, reg_index, value), do: emu |> put_in([:registers, register_name(reg_index)], value)

  def get_register32(emu, reg_index), do: emu.registers[register_name(reg_index)]
  
  def set_register8(emu, reg, value) when is_integer(reg), do: set_register8(emu, register_name8(reg), value)
  def set_register8(emu, name, value) do
    [h, t] = Atom.to_string(name) |> String.split("", trim: true)
    case t do
      "h" -> emu |> put_in([:registers, :"e#{h}x"], (emu.registers[:"e#{h}x"] &&& 0xffff00ff) ||| (value <<< 8))
      "l" -> emu |> put_in([:registers, :"e#{h}x"], (emu.registers[:"e#{h}x"] &&& 0xffffff00) ||| value)
    end
  end
  
  def get_register8(emu, reg) when is_integer(reg), do: get_register8(emu, register_name8(reg))  
  def get_register8(emu, name) do
    [h, t] = Atom.to_string(name) |> String.split("", trim: true)
    case t do
      "h" -> (emu.registers[:"e#{h}x"] >>> 8) &&& 0xff
      "l" -> emu.registers[:"e#{h}x"] &&& 0xff
    end
  end

  def set_mem32(emu, addr, value, pos \\ 0)
  def set_mem32(emu, _, _, 4), do: emu
  def set_mem32(emu, addr, value, pos) do
    emu
    |> set_mem8(addr + pos, value >>> (pos * 8))
    |> set_mem32(addr, value, pos + 1)
  end

  def get_mem32(emu, addr, pos \\ 0, val \\ 0)
  def get_mem32(_, _, 4, val), do: val
  def get_mem32(emu, addr, pos, val) do
    newval = emu |> get_mem8(addr + pos)
    emu |> get_mem32(addr, pos + 1, val ||| (newval <<< (pos * 8)))
  end

  def set_mem8(emu, addr, value) do
    <<unsigned :: integer-unsigned-8>> = <<value &&& 0xff :: integer-signed-8>>
    emu |> put_in([:memory, addr], unsigned)
  end

  def get_mem8(emu, addr), do: emu.memory[addr]

  # ? pattern matching vs. nested case (mod, rm)
  def calc_mem_addr(  _, %ModRM{mod: 0, rm:  5, disp: disp}), do: disp
  def calc_mem_addr(emu, %ModRM{mod: 0, rm: rm})            , do: get_register32(emu, rm)
  def calc_mem_addr(emu, %ModRM{mod: 1, rm: rm, disp: disp}), do: get_register32(emu, rm) + disp
  def calc_mem_addr(emu, %ModRM{mod: 2, rm: rm, disp: disp}), do: get_register32(emu, rm) + disp
  def calc_mem_addr(  _, %ModRM{rm: 4}),  do: raise "Not implemented ModR/M rm = 4 (SIB)"
  def calc_mem_addr(  _, %ModRM{mod: 3}), do: raise "Not implemented ModR/M mod = 3"

  def push32(emu, val) do
    emu
    |> put_in([:registers, :esp], emu.registers.esp - 4)
    |> set_mem32(emu.registers.esp - 4, val)
  end

  def pop32(emu) do
    val = emu |> get_mem32(emu.registers.esp)
    {emu |> put_in([:registers, :esp], emu.registers.esp + 4), val}
  end

  def update_eflags_sub(emu, l, r) do
    sign_l = l >>> 31
    sign_r = r >>> 31
    emu
    |> set_carry_flag((l - r) >>> 32 != 0)
    |> set_zero_flag(l - r == 0)
    |> set_sign_flag(((l - r) >>> 31 &&& 1) == 1)
    |> set_overflow_flag(sign_l != sign_r and sign_l != ((l - r) >>> 31 &&& 1))
  end

  def set_carry_flag(emu, true),     do: %{emu | eflags: emu.eflags ||| 1}
  def set_carry_flag(emu, false),     do: %{emu | eflags: emu.eflags &&& ~~~1}

  def set_zero_flag(emu, true),      do: %{emu | eflags: emu.eflags ||| (1 <<< 6)}
  def set_zero_flag(emu, false),      do: %{emu | eflags: emu.eflags &&& ~~~(1 <<< 6)}
  
  def set_sign_flag(emu, true),      do: %{emu | eflags: emu.eflags ||| (1 <<< 7)}
  def set_sign_flag(emu, false),      do: %{emu | eflags: emu.eflags &&& ~~~(1 <<< 7)}
  
  def set_overflow_flag(emu, true),  do: %{emu | eflags: emu.eflags ||| (1 <<< 11)}  
  def set_overflow_flag(emu, false),  do: %{emu | eflags: emu.eflags &&& ~~~(1 <<< 11)}  
  
  def eflag?(emu, pos), do: ((emu.eflags >>> pos) &&& 1) != 0
  def carry?(emu), do: eflag?(emu, 0)
  def zero?(emu), do: eflag?(emu, 6)
  def sign?(emu), do: eflag?(emu, 7)
  def overflow?(emu), do: eflag?(emu, 11)

  def register_name(val) do
    %{
      0 => :eax,
      1 => :ecx,
      2 => :edx,
      3 => :ebx,
      4 => :esp,
      5 => :ebp,
      6 => :esi,
      7 => :edi
    }[val]
  end

  def register_name8(val) do
    %{
      0 => :al,
      1 => :cl,
      2 => :dl,
      3 => :bl,
      4 => :ah,
      5 => :ch,
      6 => :dh,
      7 => :bh
    }[val]
  end
end