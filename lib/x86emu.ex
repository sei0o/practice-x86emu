defmodule X86emu do
  require Logger
  alias X86emu.{Instruction, Emulator}

  def run(bin_path, opts \\ []) do
    emu = create_emulator(0x7c00, 0x7c00)
    |> load_instructions(0x7c00, File.read!(bin_path))
    |> execute(opts[:verbose])
    
    unless opts[:quiet], do: emu |> dump_registers
  end

  def create_emulator(eip, esp) do
    mem = 0x0000..0xffff
    |> Stream.zip(List.duplicate(0, 0x10000))
    |> Enum.into(%{})
    
    %Emulator{eip: eip, memory: mem}
    |> put_in([:registers, :eax], 0)
    |> put_in([:registers, :ecx], 0)
    |> put_in([:registers, :edx], 0)
    |> put_in([:registers, :ebx], 0)
    |> put_in([:registers, :esp], esp)
    |> put_in([:registers, :ebp], 0)
    |> put_in([:registers, :esi], 0)    
    |> put_in([:registers, :edi], 0)
  end

  def load_instructions(emu, offset, binary, pos \\ 0)
  def load_instructions(emu, _, "", _), do: emu
  def load_instructions(emu, offset, <<inst :: size(8)>> <> rest_binary, pos) do
    emu
    |> put_in([:memory, offset + pos], inst)
    |> load_instructions(offset, rest_binary, pos + 1)
  end

  def execute(emu = %Emulator{eip: 0x00, started: true}, _), do: emu
  def execute(emu = %Emulator{eip: eip}, _) when eip > 0xffff, do: emu
  def execute(emu, verbose) do
    code = emu |> Emulator.get_code8
    emu = emu
    |> Map.put(:started, true)
    |> Instruction.do_instruction(code)
    
    if verbose do
      code |> Integer.to_string(16) |> IO.puts
      emu |> dump_registers
    end
    
    emu |> execute(verbose)
  end

  def dump_registers(emu) do
    [:eax, :ecx, :edx, :ebx, :esp, :ebp, :esi, :edi]
    |> Enum.map(fn reg ->
        val = emu.registers[reg]
        IO.puts "#{reg} = 0x#{val |> Integer.to_string(16) |> String.pad_leading(8, "0")}"
      end)
    IO.puts "eip = 0x#{emu.eip |> Integer.to_string(16) |> String.pad_leading(8, "0")}"
    IO.puts ""

    emu
  end
end
