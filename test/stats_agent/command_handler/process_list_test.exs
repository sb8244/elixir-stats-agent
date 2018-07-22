defmodule StatsAgent.CommandHandler.ProcessListTest do
  use ExUnit.Case, async: false

  alias StatsAgent.CommandHandler.ProcessList

  describe "no args" do
    test "10 processes are listed" do
      "text|" <> text = ProcessList.call("process_list")
      assert String.starts_with?(text, "+-----")
      assert text =~ "gen_server:loop/7"
      assert text =~ "code_server"

      ["PID", "Current Fn", "Init call", "Name", "Memory", "Msg Q Len", "Reductions"]
      |> Enum.each(fn header ->
        assert text =~ header
      end)
    end
  end
end
