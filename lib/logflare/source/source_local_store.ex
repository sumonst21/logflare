defmodule Logflare.Source.LocalStore do
  @moduledoc """
   Handles Redis source counter caches
  """
  alias Logflare.Source
  alias Logflare.{Sources, Users}
  alias Logflare.Sources.ClusterStore
  alias Logflare.Source.RecentLogsServer, as: RLS
  use GenServer

  @tick_interval 1_000
  @upload_local_counter_tick_interval 500

  # def start_link(%{source: %Source{} = source} = args, opts) do
  def start_link(%RLS{} = args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]}
    }
  end

  def init(args) do
    tick()
    upload_local_counter_tick()

    {:ok, args}
  end

  def handle_info(:tick, %{source_id: source_id} = state) do
    tick()

    source = Sources.Cache.get_by_id(source_id)

    {:ok, total_log_count} = ClusterStore.get_total_log_count(source)

    {:ok, prev_max} = ClusterStore.get_max_rate(source)
    {:ok, buffer} = ClusterStore.get_buffer_count(source)
    {:ok, avg} = ClusterStore.get_default_avg_rate(source)
    {:ok, prev_source_rate} = ClusterStore.get_prev_counter(source, period: :second)
    {:ok, last_source_rate} = ClusterStore.get_current_counter(source, period: :second)

    max = Enum.max([prev_max, prev_source_rate])

    rates_payload = %{
      last_rate: prev_source_rate || 0,
      rate: prev_source_rate || 0,
      average_rate: round(avg),
      max_rate: max || 0,
      source_token: source.token
    }

    buffer_payload = %{source_token: state.source_id, buffer: buffer}
    log_count_payload = %{source_token: state.source_id, log_count: total_log_count}

    Source.ChannelTopics.broadcast_rates(rates_payload)

    if buffer > 0 do
      Source.ChannelTopics.broadcast_buffer(buffer_payload)
    end

    if total_log_count > 0 do
      Source.ChannelTopics.broadcast_log_count(log_count_payload)
    end

    if max > prev_max do
      ClusterStore.set_max_rate(source_id, max)
    end

    {:ok, last_source_minute_rate} = ClusterStore.get_current_counter(source, period: :minute)
    {:ok, last_user_minute_rate} = ClusterStore.get_current_counter(source.user, period: :minute)

    Users.API.Cache.put_user_rate(source.user, last_user_minute_rate)
    Users.API.Cache.put_source_rate(source, last_source_minute_rate)

    {:noreply, state}
  end

  def handle_info(:upload_local_counter, state) do
    upload_local_counter_tick()
    source = Sources.Cache.get_by_id(state.source_id)
    val = Sources.Cache.get_and_reset_local_counter(state.source_id)
    ClusterStore.increment_cluster_counters(source, val)
    {:noreply, state}
  end

  def tick() do
    Process.send_after(self(), :tick, @tick_interval)
  end

  def upload_local_counter_tick() do
    Process.send_after(self(), :upload_local_counter, @upload_local_counter_tick_interval)
  end
end
