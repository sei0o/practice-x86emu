defmodule X86emuTest do
  use ExUnit.Case
  doctest X86emu

  test "greets the world" do
    assert X86emu.hello() == :world
  end
end
