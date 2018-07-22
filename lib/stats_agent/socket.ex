defmodule StatsAgent.Socket do
  @moduledoc false
  require Logger
  alias Phoenix.Channels.GenSocketClient
  @behaviour GenSocketClient

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(opts) do
    GenSocketClient.start_link(
      __MODULE__,
      Phoenix.Channels.GenSocketClient.Transport.WebSocketClient,
      opts
    )
  end

  def init(opts) do
    url = Keyword.fetch!(opts, :url)
    authentication_secret = Keyword.fetch!(opts, :authentication_secret)
    application_name = Keyword.fetch!(opts, :application_name)
    connect_interval_s = Keyword.get(opts, :connect_interval_s, 3)
    encryption_key = Keyword.fetch!(opts, :encryption_key)

    server_id =
      case Keyword.get(opts, :server_id) do
        nil ->
          {:ok, host} = :inet.gethostname()
          to_string(host)

        id ->
          id
      end

    url_params = [
      application_name: application_name,
      token: authentication_secret,
      server_id: server_id
    ]

    state = %{
      first_join: true,
      application_name: application_name,
      connect_interval_s: connect_interval_s,
      server_id: server_id,
      encryption_key: encryption_key
    }

    {:connect, url, url_params, state}
  end

  def handle_message(
        topic,
        "dispatch_command",
        %{"command_id" => cid, "encrypted_command" => encrypted_command},
        transport,
        state = %{encryption_key: key, server_id: server_id}
      ) do
    {:ok, command} = StatsAgent.Encryption.decrypt(encrypted_command, key: key)
    {:ok, response} = StatsAgent.CommandHandler.call(command)

    {:ok, _} =
      GenSocketClient.push(transport, topic, "collect_results", %{
        command_id: cid,
        encrypted_response: StatsAgent.Encryption.encrypt(response, key: key),
        server_id: server_id,
        collected_at_ms: System.os_time(:milliseconds)
      })

    {:ok, state}
  end

  def handle_message(topic, event, payload, _transport, state) do
    Logger.warn("unhandled message on topic #{topic}: #{event} #{inspect(payload)}")
    {:ok, state}
  end

  def handle_connected(transport, state = %{application_name: app_name}) do
    Logger.debug("connected")
    GenSocketClient.join(transport, "server:#{app_name}")
    {:ok, state}
  end

  def handle_disconnected(reason, state = %{connect_interval_s: connect_interval_s}) do
    Logger.error("disconnected: #{inspect(reason)}")
    Process.send_after(self(), :connect, :timer.seconds(connect_interval_s))
    {:ok, state}
  end

  def handle_joined(topic, _payload, _transport, state) do
    Logger.debug("joined the topic #{topic}")
    {:ok, state}
  end

  def handle_join_error(topic, payload, _transport, state) do
    Logger.error("join error on the topic #{topic}: #{inspect(payload)}")
    {:ok, state}
  end

  def handle_channel_closed(
        topic,
        payload,
        _transport,
        state = %{connect_interval_s: connect_interval_s}
      ) do
    Logger.error(
      "disconnected from the topic #{topic}: #{inspect(payload)} reconnecting in #{
        connect_interval_s
      }s"
    )

    Process.send_after(self(), {:join, topic}, :timer.seconds(connect_interval_s))
    {:ok, state}
  end

  def handle_reply(_topic, _ref, %{"response" => response, "status" => "ok"}, _transport, state)
      when response == %{} do
    {:ok, state}
  end

  def handle_reply(topic, _ref, payload, _transport, state) do
    Logger.warn("unhandled reply on topic #{topic}: #{inspect(payload)}")
    {:ok, state}
  end

  def handle_info(:connect, _transport, state) do
    Logger.info("connecting")
    {:connect, state}
  end

  def handle_info({:join, topic}, transport, state = %{connect_interval_s: connect_interval_s}) do
    Logger.debug("joining the topic #{topic}")

    case GenSocketClient.join(transport, topic) do
      {:error, reason} ->
        Logger.error("error joining the topic #{topic}: #{inspect(reason)}")
        Process.send_after(self(), {:join, topic}, :timer.seconds(connect_interval_s))

      {:ok, _ref} ->
        :ok
    end

    {:ok, state}
  end

  def handle_info(message, _transport, state) do
    Logger.warn("Unhandled info #{inspect(message)}")
    {:ok, state}
  end

  def handle_call(message, _from, _transport, state) do
    Logger.warn("Unhandled handle_call #{inspect(message)}")
    {:noreply, state}
  end
end
