defmodule StatsAgent.CommandHandlerTest do
  use ExUnit.Case, async: true

  alias StatsAgent.CommandHandler

  defmodule EchoHandler do
    def call("echo") do
      "echo"
    end

    def call(_), do: :unmatched
  end

  defmodule PingHandler do
    def call("ping") do
      "pong"
    end

    def call(_), do: :unmatched
  end

  test "no handlers will return an error" do
    assert CommandHandler.call("nope", handlers: []) ==
             {:error, "No handler matched the requested command: nope"}
  end

  test "unmatched handlers will return an error" do
    assert CommandHandler.call("nope", handlers: [EchoHandler, PingHandler]) ==
             {:error, "No handler matched the requested command: nope"}
  end

  test "a matched handler will return the result of the handler" do
    assert CommandHandler.call("echo", handlers: [EchoHandler, PingHandler]) == {:ok, "echo"}
    assert CommandHandler.call("ping", handlers: [EchoHandler, PingHandler]) == {:ok, "pong"}
  end

  describe "default handlers" do
    test "all_system_stats returns a JSON payload" do
      {:ok, "stats|" <> stats_json} = CommandHandler.call("all_system_stats")
      payload = Poison.decode!(stats_json)
      assert Map.keys(payload) == ["collected_at_ms", "stats"]
    end

    test "process_list returns a text payload" do
      {:ok, "text|" <> text} = CommandHandler.call("process_list")
      assert String.starts_with?(text, "+-----")
      assert text =~ "gen_server:loop/7"
      assert text =~ "code_server"
    end
  end
end
