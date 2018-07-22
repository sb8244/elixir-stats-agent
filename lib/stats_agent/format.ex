defmodule StatsAgent.Format do
  def format_pid(pid) do
    "#PID" <> formatted = inspect(pid)
    formatted
  end

  def format_bytes(b) do
    float_bytes = b / 1
    format_bytes(float_bytes, ["B", "KB", "MB"])
  end

  defp format_bytes(b, [cur_unit | units]) do
    if length(units) > 0 and b >= 1024 do
      format_bytes(b / 1024, units)
    else
      :io_lib.format("~.2f ~s", [b, cur_unit])
      |> IO.iodata_to_binary()
    end
  end

  defp format_bytes(mb, []) do
    :io_lib.format("~.2f MB", [mb])
    |> IO.iodata_to_binary()
  end
end
