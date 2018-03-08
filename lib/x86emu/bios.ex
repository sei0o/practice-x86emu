defmodule X86emu.BIOS do
  import X86emu.Emulator
  alias X86emu.IOAccess
  use Bitwise
  @bios_to_terminal %{0 => 0, 1 => 4, 2 => 2, 3 => 6, 4 => 1, 5 => 5, 6 => 3, 7 => 7}

  def put_string(charlist), do: put_string(charlist, length(charlist))
  def put_string(_charlist, 0), do: nil
  def put_string([hch | tail], size) do
    IOAccess.io_out8(0x03f8, hch)
    put_string(tail, size - 1)
  end

  def bios_video_teletype(emu) do
    color = get_register8(emu, :bl) &&& 0x0f
    chr = get_register8 emu, :al
    term_color = @bios_to_terminal[color &&& 0x07]
    bright = if (color &&& 0x08) != 0, do: IO.ANSI.bright(), else: ""
    put_string to_charlist(bright <> IO.ANSI.color(term_color) <> <<chr>> <> IO.ANSI.reset)
  end

  def bios_video(emu) do
    case get_register8 emu, :ah do
      0x0e -> bios_video_teletype(emu)
      other -> raise "Not implemented BIOS video function: 0x#{other |> Integer.to_string(16)}"
    end
    emu
  end
end