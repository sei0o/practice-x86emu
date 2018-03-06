defmodule X86emu.ModRM do
  defstruct mod: 0, reg: 0, rm: 0, sib: 0, disp: 0
end