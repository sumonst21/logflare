defmodule Logflare.Logs.Search.Utils do
  @moduledoc """
  Utilities for Logs search and Logs live view modules
  """
  require Logger

  def pid_to_string(pid) when is_pid(pid) do
    pid
    |> :erlang.pid_to_list()
    |> to_string()
  end

  def pid_source_to_string(pid, source) do
    "#{pid_to_string(pid)} for #{source.token}"
  end

  def format_error(%Tesla.Env{body: body}) do
    body
    |> Poison.decode!()
    |> Map.get("error")
    |> Map.get("message")
  end

  def format_error(e), do: e

  def log_lv_received_info(msg, source) do
    Logger.info("#{pid_sid(source)} received #{msg} info msg...")
  end

  def log_lv(source, msg) do
    Logger.info("#{pid_sid(source)} #{msg}")
  end

  def log_lv_executing_query(source) do
    Logger.info("#{pid_sid(source)} executing tail search query...")
  end

  def log_lv_received_event(event_name, source) do
    Logger.info("#{pid_sid(source)} received #{event_name} event")
  end

  def gen_search_tip() do
    tips = [
      "Search is case sensitive.",
      "Exact match an integer (e.g. `metadata.response.status:500`).",
      "Integers support greater and less than symobols (e.g. `metadata.response.origin_time:<1000`).",
      ~s|Exact match a string in a field (e.g. `metadata.response.cf-ray:"505c16f9a752cec8-IAD"`).|,
      "Timestamps support greater and less than symbols (e.g. `timestamp:>=2019-07-01`).",
      ~s|Match a field with regex (e.g. `metadata.browser:~"Firefox 5\\d"`).|,
      "Search between times with multiple fields (e.g. `timestamp:>=2019-07-01 timestamp:<=2019-07-02`).",
      "Default behavoir is to search the log message field (e.g. `error`).",
      "Turn off Live Search to search the full history of this source."
    ]

    Enum.random(tips)
  end

  defp pid_sid(source) do
    pid_source_to_string(self(), source)
  end
end
