defmodule LogflareWeb.GlobalLogMetricsLV do
  @moduledoc false
  alias Logflare.SystemMetrics.AllLogsLogged
  import Number.Delimit, only: [number_to_delimited: 1]
  use Phoenix.LiveView

  def render(assigns) do
    ~L"""
    <h3>That's <span><%= @log_count %></span> events logged to date</h3>
    <h3>Counting <span><%= @per_second %></span> events per second</h3>
    """
  end

  def mount(_session, socket) do
    if connected?(socket), do: :timer.send_interval(250, self(), :tick)

    {:ok, put_data(socket)}
  end

  def handle_info(:tick, socket) do
    {:noreply, put_data(socket)}
  end

  defp put_data(socket) do
    log_count = AllLogsLogged.Poller.total_logs_logged_cluster()
    total_logs_per_second = AllLogsLogged.Poller.logs_last_second_cluster()
    log_count = number_to_delimited(log_count)
    total_logs_per_second = number_to_delimited(total_logs_per_second)

    assign(socket, log_count: log_count, per_second: total_logs_per_second)
  end
end
