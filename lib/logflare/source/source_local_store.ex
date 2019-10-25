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

  def start_link(%RLS{} = rls, opts \\ []) do
    GenServer.start_link(__MODULE__, rls, Keyword.merge([name: name(rls.source_id)], opts))
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

    max =
      if prev_source_rate > prev_max do
        ClusterStore.set_max_rate(source_id, prev_source_rate)
        prev_source_rate
      else
        prev_max
      end

    rates_payload = %{
      last_rate: prev_source_rate || 0,
      rate: prev_source_rate || 0,
      average_rate: round(avg),
      max_rate: max || 0,
      source_token: source.token
    }

    buffer_payload = %{source_token: state.source_id, buffer: buffer}

    log_count_payload = %{source_token: state.source_id, log_count: total_log_count}

    if rates_payload.average_rate > 0 or rates_payload.last_rate > 0 or
         Map.get(state, :rates_payload) != rates_payload do
      Source.ChannelTopics.broadcast_rates(rates_payload)
    end

    if buffer_payload > 0 do
      Source.ChannelTopics.broadcast_buffer(buffer_payload)
    end

    if Map.get(state, :log_count_payload) != log_count_payload do
      Source.ChannelTopics.broadcast_log_count(log_count_payload)
    end

    {:ok, last_source_minute_rate} = ClusterStore.get_current_counter(source, period: :minute)
    {:ok, last_user_minute_rate} = ClusterStore.get_current_counter(source.user, period: :minute)

    Users.API.Cache.put_source_rate(source, last_source_minute_rate)
    Users.API.Cache.put_user_rate(source.user, last_user_minute_rate)

    state =
      state
      |> Map.put(:rates_payload, rates_payload)
      |> Map.put(:buffer_payload, buffer_payload)
      |> Map.put(:log_count_payload, log_count_payload)

    {:noreply, state}
  end

  def broadcast_on_join(source_id) do
    GenServer.cast(name(source_id), :broadcast_on_join)
  end

  def handle_cast(:broadcast_on_join, state) do
    Source.ChannelTopics.broadcast_rates(state.rates_payload)
    Source.ChannelTopics.broadcast_buffer(state.buffer_payload)
    Source.ChannelTopics.broadcast_log_count(state.log_count_payload)

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

  def name(source_id) do
    :"#{source_id}_local_store_server"
  end
end
