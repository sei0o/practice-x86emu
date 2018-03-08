defmodule X86emu.Instruction.Macros do
  defmacro jcc(name, checkfn) do
    quote do
      def unquote(:"j#{name}")(emu) do
        emu |> seek(if unquote(checkfn)(emu), do: 2 + get_code8_signed(emu), else: 2)
      end
      def unquote(:"jn#{name}")(emu) do
        emu |> seek(if unquote(checkfn)(emu), do: 2, else: 2 + get_code8_signed(emu))
      end
    end
  end    
end

defmodule X86emu.Instruction do
  require X86emu.Instruction.Macros
  import X86emu.Emulator
  alias X86emu.{IOAccess, BIOS}
  use Bitwise

  def do_instruction(emu, 0x01), do: add_rm32_r32(emu)
  def do_instruction(emu, 0x3b), do: cmp_r32_rm32(emu)
  def do_instruction(emu, 0x3c), do: cmp_al_imm8(emu)
  def do_instruction(emu, code) when code in 0x40..0x47, do: inc_r32(emu)
  def do_instruction(emu, code) when code in 0x50..0x57, do: push_r32(emu)
  def do_instruction(emu, code) when code in 0x58..0x5f, do: pop_r32(emu)
  def do_instruction(emu, 0x6a), do: push_imm8(emu)
  def do_instruction(emu, 0x74), do: je(emu)
  def do_instruction(emu, 0x7e), do: jle(emu)
  def do_instruction(emu, 0x83), do: handle_code83(emu)
  def do_instruction(emu, 0x89), do: mov_rm32_r32(emu)
  def do_instruction(emu, 0x8a), do: mov_r8_rm8(emu)
  def do_instruction(emu, 0x8b), do: mov_r32_rm32(emu)
  def do_instruction(emu, code) when code in 0xb0..0xb7, do: mov_r8_imm8(emu)
  def do_instruction(emu, code) when code in 0xb8..0xbf, do: mov_r32_imm32(emu)
  def do_instruction(emu, 0xc3), do: ret(emu)
  def do_instruction(emu, 0xc7), do: mov_rm32_imm32(emu)
  def do_instruction(emu, 0xc9), do: leave(emu)
  def do_instruction(emu, 0xcd), do: int(emu)
  def do_instruction(emu, 0xe8), do: call_rel32(emu)
  def do_instruction(emu, 0xe9), do: near_jump(emu)
  def do_instruction(emu, 0xeb), do: short_jump(emu)
  def do_instruction(emu, 0xec), do: in_al_dx(emu)
  def do_instruction(emu, 0xee), do: out_dx_al(emu)
  def do_instruction(emu, 0xff), do: handle_codeff(emu)
  def do_instruction(emu, code) do 
    raise "Not Implemented: #{code |> Integer.to_string(16)} at 0x#{emu.eip |> Integer.to_string(16)}"
  end

  def mov_r8_rm8(emu) do
    {emu, modrm} = emu |> seek(1) |> read_modrm
    rm8 = get_rm8 emu, modrm
    emu
    |> set_register8(modrm.reg, rm8)
  end
  
  def mov_r8_imm8(emu) do
    reg = get_code8(emu) - 0xb0
    emu
    |> set_register8(reg, get_code8(emu, 1))
    |> seek(2)
  end

  def mov_r32_imm32(emu) do
    reg = register_name(get_code8(emu) - 0xb8)
    val = get_code32 emu, 1
    emu
    |> put_in([:registers, reg], val)
    |> seek(5)
  end

  def mov_rm32_imm32(emu) do
    {emu, modrm} = emu |> seek(1) |> read_modrm
    val = get_code32 emu # get immediate value
    emu
    |> seek(4)
    |> set_rm32(modrm, val)
  end

  def mov_rm8_r8(emu) do
    {emu, modrm} = emu |> seek(1) |> read_modrm
    r8 = get_register8 emu, modrm.reg
    emu |> set_rm8(modrm, r8)
  end

  def mov_rm32_r32(emu) do
    {emu, modrm} = emu |> seek(1) |> read_modrm
    emu |> set_rm32(modrm, get_register32(emu, modrm.reg))
  end

  def mov_r32_rm32(emu) do
    {emu, modrm} = emu |> seek(1) |> read_modrm
    emu |> set_register32(modrm.reg, get_rm32(emu, modrm))
  end

  def add_rm32_r32(emu) do
    {emu, modrm} = emu |> seek(1) |> read_modrm
    rm32 = get_rm32 emu, modrm
    r32 = get_register32 emu, modrm.reg
    emu |> set_rm32(modrm, rm32 + r32)
  end

  def add_rm32_imm8(emu, modrm) do
    rm32 = get_rm32 emu, modrm
    imm8 = get_code8_signed emu
    emu |> seek(1) |> set_rm32(modrm, rm32 + imm8)
  end

  def sub_rm32_imm8(emu, modrm) do
    rm32 = get_rm32 emu, modrm
    imm8 = get_code8_signed emu
    emu
    |> seek(1)
    |> set_rm32(modrm, rm32 - imm8)
    |> update_eflags_sub(rm32, imm8)
  end

  def inc_rm32(emu, modrm) do
    val = get_rm32 emu, modrm
    emu |> set_rm32(modrm, val + 1)
  end

  def inc_r32(emu) do
    reg_index = get_code8(emu) - 0x40
    r32 = get_register32 emu, reg_index
    emu
    |> set_register32(reg_index, r32 + 1)
    |> seek(1)
  end

  def short_jump(emu) do
    diff = get_code8_signed emu, 1
    emu |> seek(2 + diff) 
  end

  def near_jump(emu) do
    diff = get_code32_signed emu, 1
    emu |> seek(5 + diff)
  end

  def push_r32(emu) do
    reg_index = get_code8(emu) - 0x50
    emu |> push32(get_register32(emu, reg_index)) |> seek(1)
  end

  def push_imm32(emu) do
    val = get_code32 emu, 1
    emu |> push32(val) |> seek(5)
  end

  def push_imm8(emu) do
    val = get_code8 emu, 1
    emu |> push32(val) |> seek(2)
  end

  def pop_r32(emu) do
    reg_index = get_code8(emu) - 0x58
    {emu, val} = pop32(emu)
    emu |> set_register32(reg_index, val) |> seek(1)
  end

  def call_rel32(emu) do
    diff = get_code32_signed emu, 1
    emu
    |> push32(emu.eip + 5) # push return address
    |> seek(5 + diff)
  end

  def leave(emu) do
    {emu, val} = emu |> put_in([:registers, :esp], emu.registers.ebp) |> pop32
    emu |> put_in([:registers, :ebp], val) |> seek(1)
  end

  def ret(emu) do
    {emu, val} = pop32(emu)
    %{emu | eip: val}
  end

  def cmp_r32_rm32(emu) do
    {emu, modrm} = emu |> seek(1) |> read_modrm
    r32 = get_register32 emu, modrm.reg
    rm32 = get_rm32 emu, modrm
    emu |> update_eflags_sub(r32, rm32)
  end

  def cmp_r32_imm8(emu, modrm) do
    rm32 = get_rm32 emu, modrm
    imm8 = get_code8_signed emu
    emu |> seek(1) |> update_eflags_sub(rm32, imm8)
  end

  def cmp_al_imm8(emu) do
    al = get_register8 emu, :al
    imm8 = get_code8_signed emu, 1
    emu |> seek(2) |> update_eflags_sub(al, imm8)
  end

  X86emu.Instruction.Macros.jcc :c, :carry?
  X86emu.Instruction.Macros.jcc :z, :zero?
  X86emu.Instruction.Macros.jcc :s, :sign?
  X86emu.Instruction.Macros.jcc :o, :overflow?

  def jl(emu) do
    emu |> seek(if sign?(emu) != overflow?(emu), do: 2 + get_code8_signed(emu, 1), else: 2)
  end

  def jle(emu) do
    emu |> seek(if (sign?(emu) != overflow?(emu)) or zero?(emu), do: 2 + get_code8_signed(emu, 1), else: 2) 
  end

  def je(emu) do
    emu |> seek(if zero?(emu), do: 2 + get_code8_signed(emu, 1), else: 2)
  end

  def in_al_dx(emu) do
    addr = emu.registers.edx &&& 0xffff
    val = IOAccess.io_in8 addr
    emu |> set_register8(:al, val) |> seek(1)
  end

  def out_dx_al(emu) do
    addr = emu.registers.edx &&& 0xffff
    IOAccess.io_out8 addr, get_register8(emu, :al)
    emu |> seek(1)
  end

  def int(emu) do
    int = get_code8 emu, 1
    emu = emu |> seek(2)
    case int do
      0x10 -> emu |> BIOS.bios_video
      _ -> raise "Unknown Interrupt: 0x#{int |> Integer.to_string(16)}"
    end
  end

  def handle_code83(emu) do
    {emu, modrm} = emu |> seek(1) |> read_modrm
    case modrm.reg do
      0 -> add_rm32_imm8(emu, modrm)
      5 -> sub_rm32_imm8(emu, modrm)
      7 -> cmp_r32_imm8(emu, modrm)
      other -> raise "Not implemented: 83 with REG #{other}"
    end
  end

  def handle_codeff(emu) do
    {emu, modrm} = emu |> seek(1) |> read_modrm
    case modrm.reg do
      0 -> inc_rm32(emu, modrm)
      other -> raise "Not implemented: FF with REG #{other}"
    end
  end
end