defmodule X86emu.IOAccess do
  use Bitwise

  def io_in8(0x03f8), do: IO.getn("") |> String.to_charlist |> hd
  def io_in8(_), do: 0

  def io_out8(0x03f8, val), do: IO.write(val)
  def io_out8(_, _), do: raise "Not Implemented"
end