defmodule StatsAgent.SocketTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias StatsAgent.Socket

  @fake_opts [
    url: "url",
    authentication_secret: "authentication_secret",
    application_name: "application_name",
    encryption_key: "encryption_key",
    server_id: "server_id"
  ]

  @fake_state %{
    application_name: "application_name",
    connect_interval_s: 3,
    encryption_key: "encryption_key",
    first_join: true,
    server_id: "server_id"
  }

  # Stub  out the GenSocketClient serializer and transport mod to handle fake data

  defmodule FakeSerializer do
    def encode_message(args), do: {:ok, args}

    defmodule Fail do
      def encode_message(_), do: {:error, :fake_fail}
    end
  end

  defmodule MirrorTransportMod do
    def push_data(), do: Process.get({__MODULE__, :push})

    def push(pid, encoded) do
      Process.put({__MODULE__, :push}, {pid, encoded})
    end
  end

  describe "init/1" do
    test "the correct connect callback is returned for GenSocketClient" do
      assert Socket.init(@fake_opts) == {
        :connect,
        "url",
        [
          application_name: "application_name",
          token: "authentication_secret",
          server_id: "server_id"
        ],
        @fake_state
      }
    end

    test "connect_interval_s can be specified" do
      {_, _, _, %{connect_interval_s: 10}} =
        @fake_opts
        |> Keyword.put(:connect_interval_s, 10)
        |> Socket.init()
    end

    test "server_id defaults to the hostname" do
      {:ok, host} = :inet.gethostname()
      host = to_string(host)

      {_, _, [application_name: "application_name", token: "authentication_secret", server_id: ^host], %{server_id: ^host}} =
        @fake_opts
        |> Keyword.delete(:server_id)
        |> Socket.init()
    end
  end

  describe "handle_message/5 dispatch_command" do
    test "the command is executed and the result is pushed to the client" do
      command = StatsAgent.Encryption.encrypt("process_list", key: "encryption_key")
      Process.put({Phoenix.Channels.GenSocketClient, {:join_ref, "fake topic"}}, "join ref")
      transport = %{
        serializer: FakeSerializer,
        transport_mod: MirrorTransportMod,
        transport_pid: "a pid"
      }

      assert Socket.handle_message(
        "fake topic",
        "dispatch_command",
        %{"command_id" => "command id", "encrypted_command" => command},
        transport,
        @fake_state
      ) == {:ok, @fake_state}

      {pid, encoded} = MirrorTransportMod.push_data()

      assert pid == "a pid"
      assert ["join ref", 1, "fake topic", "collect_results", payload] = encoded

      assert %{collected_at_ms: ms, command_id: "command id", encrypted_response: resp, server_id: "server_id"} = payload
      assert is_bitstring(resp)
      assert is_integer(ms)
      {:ok, "text|" <> _} = StatsAgent.Encryption.decrypt(resp, key: "encryption_key")
    end

    test "a serializer fail does not push the response" do
      command = StatsAgent.Encryption.encrypt("process_list", key: "encryption_key")
      Process.put({Phoenix.Channels.GenSocketClient, {:join_ref, "fake topic"}}, "join ref")
      transport = %{
        serializer: FakeSerializer.Fail
      }

      assert capture_log(fn ->
        assert Socket.handle_message(
          "fake topic",
          "dispatch_command",
          %{"command_id" => "command id", "encrypted_command" => command},
          transport,
          @fake_state
        ) == {:ok, @fake_state}
      end) =~ "[error] Elixir.StatsAgent.Socket encountered error {:push, {:error, {:encoding_error, :fake_fail}}}"

      refute MirrorTransportMod.push_data()
    end

    test "an unjoined topic doesn't push a message" do
      command = StatsAgent.Encryption.encrypt("process_list", key: "encryption_key")

      assert capture_log(fn ->
        assert Socket.handle_message(
          "fake topic",
          "dispatch_command",
          %{"command_id" => "a", "encrypted_command" => command},
          %{},
          @fake_state
        ) == {:ok, @fake_state}

        refute MirrorTransportMod.push_data()
      end) =~ "error {:push, {:error, :not_joined}}"
    end

    test "an invalid encrypted_command decryption doesn't crash and doesn't push data" do
      assert capture_log(fn ->
        assert Socket.handle_message(
          "topic",
          "dispatch_command",
          %{"command_id" => "a", "encrypted_command" => "b"},
          %{},
          @fake_state
        ) == {:ok, @fake_state}

        refute MirrorTransportMod.push_data()
      end) =~ "Elixir.StatsAgent.Socket encountered error {:decryption, :error}"
    end

    test "an invalid command does not return a result" do
      command = StatsAgent.Encryption.encrypt("nope", key: "encryption_key")

      assert capture_log(fn ->
        assert Socket.handle_message(
          "fake topic",
          "dispatch_command",
          %{"command_id" => "command id", "encrypted_command" => command},
          %{},
          @fake_state
        ) == {:ok, @fake_state}
        refute MirrorTransportMod.push_data()
      end) =~ "error {:handler, {:error, \"No handler matched the requested command: nope\"}}"
    end
  end

  describe "handle_message/5 unknown command" do
    test "a warning is raised" do
      assert capture_log(fn ->
        assert Socket.handle_message(
          "fake_topic",
          "nope",
          %{},
          %{},
          @fake_state
        ) == {:ok, @fake_state}
      end) =~ "[warn]  unhandled message on topic fake_topic: nope %{}"
    end
  end

  describe "handle_connected/2" do
    test "phx_join is pushed to the transport" do
      transport = %{
        serializer: FakeSerializer,
        transport_mod: MirrorTransportMod,
        transport_pid: "a pid"
      }

      assert capture_log(fn ->
        assert Socket.handle_connected(transport, @fake_state) == {:ok, @fake_state}
      end) =~ "[debug] connected"
      assert MirrorTransportMod.push_data() == {"a pid", [1, 1, "server:#{@fake_state.application_name}", "phx_join", %{}]}
    end
  end

  describe "handle_disconnected/2" do
    test "the connection is retried in the connect interval seconds" do
      assert capture_log(fn ->
        state = @fake_state |> Map.put(:connect_interval_s, 1)
        assert Socket.handle_disconnected("killed", state) == {:ok, state}
      end) =~ "[error] disconnected: \"killed\""

      assert_receive(:connect, 1200)
    end
  end

  describe "handle_joined/2" do
    test "welcome message" do
      assert capture_log(fn ->
        assert Socket.handle_joined("a topic", %{}, %{}, @fake_state) == {:ok, @fake_state}
      end) =~ "[debug] joined the topic: a topic"
    end
  end

  describe "handle_join_error/2" do
    test "error message" do
      assert capture_log(fn ->
        assert Socket.handle_join_error("a topic", %{a: "x"}, %{}, @fake_state) == {:ok, @fake_state}
      end) =~ "[error] join error on the topic a topic: %{a: \"x\"}"
    end
  end

  describe "handle_channel_closed/4" do
    test "the topic is rejoined in connect_interval_s" do
      assert capture_log(fn ->
        state = @fake_state |> Map.put(:connect_interval_s, 1)
        assert Socket.handle_channel_closed("a topic", %{a: "x"}, %{}, state) == {:ok, state}
      end) =~ "[error] disconnected from the topic a topic: %{a: \"x\"} reconnecting in 1s"

      assert_receive({:join, "a topic"}, 1200)
    end
  end

  describe "handle_reply/5" do
    test "empty response, ok status is ignored" do
      assert Socket.handle_reply("topic", "ref", %{"response" => %{}, "status" => "ok"}, %{}, @fake_state) == {:ok, @fake_state}
    end

    test "not empty response, ok status is warned" do
      assert capture_log(fn ->
        assert Socket.handle_reply("topic", "ref", %{"response" => %{"x" => 1}, "status" => "ok"}, %{}, @fake_state) == {:ok, @fake_state}
      end) =~ "[warn]  unhandled reply on topic topic: %{\"response\" => %{\"x\" => 1}, \"status\" => \"ok\"}"
    end
  end

  describe "handle_info :connect" do
    test "connect tuple is returned" do
      assert capture_log(fn ->
        assert Socket.handle_info(:connect, %{}, @fake_state) == {:connect, @fake_state}
      end) =~ "[info]  connecting"
    end
  end

  describe "handle_info :join" do
    test "a join error retries in connect_interval_s" do
      log = capture_log(fn ->
        transport = %{
          serializer: FakeSerializer.Fail
        }
        state = @fake_state |> Map.put(:connect_interval_s, 1)
        assert Socket.handle_info({:join, "a topic"}, transport, state) == {:ok, state}
      end)

      assert log =~ "[debug] joining the topic: a topic"
      assert log =~ "[error] error joining the topic a topic: {:encoding_error, :fake_fail}"

      assert_receive({:join, "a topic"}, 1200)
    end

    test "a join success is all good" do
      assert capture_log(fn ->
        transport = %{
          serializer: FakeSerializer,
          transport_mod: MirrorTransportMod,
          transport_pid: "a pid"
        }
        assert Socket.handle_info({:join, "a topic"}, transport, @fake_state) == {:ok, @fake_state}
      end) =~ "[debug] joining the topic: a topic"

      refute_receive({:join, "a topic"}, 1200)

      assert MirrorTransportMod.push_data() == {"a pid", [1, 1, "a topic", "phx_join", %{}]}
    end
  end

  describe "handle_info/3 unhandled" do
    test "a warning is raised" do
      assert capture_log(fn ->
        assert Socket.handle_info(:message, %{}, @fake_state) == {:ok, @fake_state}
      end) =~ "[warn]  Unhandled handle_info :message"
    end
  end

  describe "handle_call/4 unhandled" do
    test "a warning is raised" do
      assert capture_log(fn ->
        assert Socket.handle_call(:message, self(), %{}, @fake_state) == {:noreply, @fake_state}
      end) =~ "[warn]  Unhandled handle_call :message"
    end
  end
end
