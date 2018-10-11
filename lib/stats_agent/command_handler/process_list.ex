defmodule StatsAgent.CommandHandler.ProcessList do
  @sort_types %{
    "memory" => :memory,
    "message_queue_len" => :message_queue_len,
    "heap_size" => :heap_size,
    "total_heap_size" => :total_heap_size,
    "reductions" => :reductions
  }

  alias StatsAgent.Format

  def call("process_list"), do: call("process_list|")

  def call("process_list|" <> str_args) do
    args = URI.decode_query(str_args)
    size = Map.get(args, "count", "10") |> String.to_integer()
    sort_type_name = Map.get(args, "by", "memory")
    sort_type = Map.fetch!(@sort_types, sort_type_name)

    plaintext =
      :recon.proc_count(sort_type, size)
      |> Enum.map(&map_proc_info/1)
      |> format_results()

    "text|#{plaintext}"
  end

  def call(_), do: :unmatched

  defp format_results(results) do
    Scribe.format(
      results,
      data: [
        {"PID", :pid},
        {"Current Fn", :current_fn},
        {"Init call", :initial_call},
        {"Name", :registered_name},
        {"Memory", :memory},
        {"Msg Q Len", :message_queue_len},
        {"Reductions", :reductions_total},
        {"Heap Size", :heap_size},
        {"Total Heap Size", :total_heap_size}
      ],
      colorize: false
    )
  end

  defp map_proc_info({pid, _, _}) do
    # Load the process info to get a full picture of process: Elixir vs Erlang treated different
    proc_info = :recon.info(pid)

    Keyword.get(proc_info, :meta)
    |> case do
      :undefined ->
        # The process is not alive anymore
        %{
          pid: Format.format_pid(pid),
          alive: false
        }

      _ ->
        %{
          pid: Format.format_pid(pid),
          current_fn: current_function(proc_info),
          initial_call: initial_call(proc_info),
          registered_name: registered_name(proc_info),
          memory: memory(proc_info),
          message_queue_len: message_queue_len(proc_info),
          reductions_total: reductions(proc_info),
          heap_size: heap_size(proc_info),
          total_heap_size: total_heap_size(proc_info)
        }
    end
  end

  defp format_mfa({mod, fn_name, arity}) do
    "#{mod}:#{fn_name}/#{arity}"
  end

  defp current_function(info) do
    Keyword.get(info, :location, [])
    |> Keyword.get(:current_stacktrace, [])
    |> List.first()
    |> case do
      {m, f, arity, _} ->
        format_mfa({m, f, arity})

      _ ->
        "er"
    end
  end

  defp initial_call(info) do
    meta = Keyword.get(info, :meta, [])

    Keyword.get(meta, :dictionary, [])
    |> Keyword.get(:"$initial_call")
    |> case do
      mfa = {_, _, _} ->
        mfa

      nil ->
        # this is an erlang process
        Keyword.get(info, :location, [])
        |> Keyword.get(:initial_call, {"er", "er", 0})
    end
    |> format_mfa()
  end

  defp registered_name(info) do
    Keyword.get(info, :meta, [])
    |> Keyword.get(:registered_name, [])
    |> case do
      [] -> nil
      name -> to_string(name)
    end
  end

  defp memory(info) do
    Keyword.get(info, :memory_used, [])
    |> Keyword.get(:memory, 0)
    |> Format.format_bytes()
  end

  defp message_queue_len(info) do
    Keyword.get(info, :memory_used, [])
    |> Keyword.get(:message_queue_len, "er")
  end

  defp reductions(info) do
    Keyword.get(info, :work, [])
    |> Keyword.get(:reductions, "er")
  end

  defp heap_size(info) do
    Keyword.get(info, :memory_used, [])
    |> Keyword.get(:heap_size, -1)
  end

  defp total_heap_size(info) do
    Keyword.get(info, :memory_used, [])
    |> Keyword.get(:total_heap_size, -1)
  end
end
