defmodule X86emu do
  use Bitwise
  require Logger

  @register_name %{
    0 => :eax,
    1 => :ecx,
    2 => :edx,
    3 => :ebx,
    4 => :esp,
    5 => :ebp,
    6 => :esi,
    7 => :edi
  }

  defmodule Emulator do
    @behaviour Access

    defstruct registers: %{}, eflags: 0, memory: %{}, eip: 0, started: false

    # see: https://github.com/benjamintanweihao/chip8/blob/master/lib/chip8/io.ex
    defdelegate fetch(a, b), to: Map
    defdelegate get(a, b, c), to: Map
    defdelegate get_and_update(a, b, c), to: Map
    defdelegate pop(a, b), to: Map
  end

  def run(bin_path) do
    create_emulator(0x7c00, 0x7c00)
    |> load_instructions(0x7c00, File.read!(bin_path))
    |> execute
    |> dump_registers
  end

  def create_emulator(eip, esp) do
    mem = 0x000..0xffff
    |> Stream.zip(List.duplicate(0, 0x10000))
    |> Enum.into(%{})
    
    %Emulator{eip: eip, memory: mem}
    |> put_in([:registers, :esp], esp)
  end

  def load_instructions(emu, offset, binary, pos \\ 0)
  def load_instructions(emu, _, "", _), do: emu
  def load_instructions(emu, offset, <<inst :: size(8)>> <> rest_binary, pos) do
    emu
    |> put_in([:memory, offset + pos], inst)
    |> load_instructions(offset, rest_binary, pos + 1)
  end

  def execute(emu = %Emulator{eip: 0x00, started: true}), do: emu
  def execute(emu = %Emulator{eip: eip}) when eip > 0xFFFF, do: emu
  def execute(emu) do
    code = emu |> get_code8(0)
    emu 
    |> Map.put(:started, true)
    |> do_instruction(code)
  end

  def do_instruction(emu, code) when code in 0xb8..(0xb8+7), do: mov_r32_imm32(emu)
  def do_instruction(emu, 0xe9), do: near_jump(emu)
  def do_instruction(emu, 0xeb), do: short_jump(emu)
  def do_instruction(emu, code) do 
    raise "Not Implemented: #{code} at 0x#{emu.eip |> Integer.to_string(16)}"
  end

  def mov_r32_imm32(emu) do
    reg = @register_name[get_code8(emu, 0) - 0xb8]
    val = get_code32 emu, 1
    emu
    |> put_in([:registers, reg], val)
    |> Map.put(:eip, emu.eip + 5)
  end

  def short_jump(emu) do
    diff = get_code8_signed emu, 1
    %{emu | eip: emu.eip + 2 + diff} 
  end

  def near_jump(emu) do
    diff = get_code32_signed emu, 1
    %{emu | eip: emu.eip + 5 + diff}
  end

  def get_code8(emu, offset) do
    emu.memory[emu.eip + offset]
  end

  def get_code8_signed(emu, offset) do
    <<ret :: integer-signed-8>> = <<get_code8(emu, offset) :: integer-unsigned-8>>
    ret
  end

  def get_code32(emu, offset, byt \\ 3)
  def get_code32(emu, offset, 0), do: get_code8(emu, offset)
  def get_code32(emu, offset, byt) do
    get_code8(emu, offset + byt) <<< byt * 8 ||| get_code32(emu, offset, byt - 1)
  end

  def get_code32_signed(emu, offset) do
    <<ret :: integer-signed-32>> = <<get_code32(emu, offset) :: integer-unsigned-32>>
    ret
  end

  def dump_registers(emu) do
    emu.registers
    |> Enum.map(fn {reg, val} ->
        IO.puts "#{reg} = 0x#{val |> Integer.to_string(16) |> String.pad_leading(8, "0")}"
      end)
  end
end
