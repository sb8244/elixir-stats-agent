defmodule StatsAgent.FormatTest do
  use ExUnit.Case, async: true
  alias StatsAgent.Format

  @kb_boundary 1024
  @mb_boundary 1_048_576

  describe "format_pid" do
    test "the pid is formatted like <0.0.0>" do
      pid = :erlang.list_to_pid('<0.1.2>')
      assert Format.format_pid(pid) == "<0.1.2>"
    end
  end

  describe "format_bytes" do
    test "< 1024 is in bytes" do
      assert Format.format_bytes(@kb_boundary - 1) == "1023.00 B"
    end

    test "= #{@kb_boundary} is in KB" do
      assert Format.format_bytes(@kb_boundary) == "1.00 KB"
    end

    test "> #{@kb_boundary} < #{@mb_boundary} is in KB, but with precision lost" do
      assert Format.format_bytes(@mb_boundary - 1) == "1024.00 KB"
    end

    test "decimal places are provied for bytes in between ranges" do
      assert Format.format_bytes(@mb_boundary - @kb_boundary - @kb_boundary / 2) == "1022.50 KB"
    end

    test "= #{@mb_boundary} is in MB" do
      assert Format.format_bytes(@mb_boundary) == "1.00 MB"
    end

    test "> #{@mb_boundary} is always in MB" do
      assert Format.format_bytes(@mb_boundary * 100_000_000) == "100000000.00 MB"
    end
  end
end
