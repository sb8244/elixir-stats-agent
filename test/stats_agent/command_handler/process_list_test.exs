defmodule StatsAgent.CommandHandler.ProcessListTest do
  use ExUnit.Case, async: false

  alias StatsAgent.CommandHandler.ProcessList

  describe "no args" do
    test "10 processes are listed" do
      "text|" <> text = ProcessList.call("process_list")
      assert String.starts_with?(text, "+-----")
      assert text |> String.split("\n") |> length() == 10 + 5
      assert text =~ "gen_server:loop/7"
      assert text =~ "code_server"

      ["PID", "Current Fn", "Init call", "Name", "Memory", "Msg Q Len", "Reductions", "Heap Size", "Total Heap Size"]
      |> Enum.each(fn header ->
        assert text =~ header
      end)
    end

    test "count arg is accepted and used" do
      "text|" <> text = ProcessList.call("process_list|count=1")
      assert String.starts_with?(text, "+-----")
      assert text |> String.split("\n") |> length() == 1 + 5
    end

    test "various 'by' types are supported by recon" do
      ~w(memory message_queue_len heap_size total_heap_size reductions)
      |> Enum.each(fn by ->
        "text|" <> text = ProcessList.call("process_list|by=#{by}")
        assert String.starts_with?(text, "+-----")
      end)
    end
  end
end
