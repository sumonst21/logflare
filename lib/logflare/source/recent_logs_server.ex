defmodule Logflare.Source.RecentLogsServer do
  @moduledoc """
  Manages the individual table for the source. Limits things in the table to 1000. Manages TTL for
  things in the table. Handles loading the table from the disk if found on startup.
  """
  use Publicist
  use TypedStruct

  typedstruct do
    field :source_id, atom(), enforce: true
    field :notifications_every, integer(), default: 60_000
    field :inserts_since_boot, integer(), default: 0
    field :bigquery_project_id, atom()
    field :bigquery_dataset_id, binary()
    field :total_cluster_inserts, integer(), default: 0
  end

  use GenServer

  alias Logflare.Sources.Counters
  alias Logflare.Google.{BigQuery, BigQuery.GenUtils}
  alias Logflare.Source.BigQuery.{Schema, Pipeline, Buffer}

  alias Logflare.Source.{
    Data,
    EmailNotificationServer,
    TextNotificationServer,
    WebhookNotificationServer,
    SlackHookServer
  }

  alias Logflare.Source.RateCounterServer, as: RCS
  alias Logflare.LogEvent, as: LE
  alias Logflare.Source
  alias Logflare.Logs.SearchQueryExecutor
  alias Logflare.Tracker
  alias __MODULE__, as: RLS

  require Logger

  @prune_timer 1_000
  @broadcast_every 250

  def start_link(%__MODULE__{source_id: source_id} = rls) when is_atom(source_id) do
    GenServer.start_link(__MODULE__, rls, name: source_id)
  end

  ## Client
  @spec init(RLS.t()) :: {:ok, RLS.t(), {:continue, :boot}}
  def init(rls) do
    Process.flag(:trap_exit, true)
    prune()

    broadcast()

    {:ok, rls, {:continue, :boot}}
  end

  def push(source_id, %LE{} = log_event) do
    GenServer.cast(source_id, {:push, source_id, log_event})
  end

  ## Server

  def handle_continue(:boot, %__MODULE__{source_id: source_id} = rls) when is_atom(source_id) do
    %{
      user_id: user_id,
      bigquery_table_ttl: bigquery_table_ttl,
      bigquery_project_id: bigquery_project_id,
      bigquery_dataset_location: bigquery_dataset_location,
      bigquery_dataset_id: bigquery_dataset_id
    } = GenUtils.get_bq_user_info(source_id)

    BigQuery.init_table!(
      user_id,
      source_id,
      bigquery_project_id,
      bigquery_table_ttl,
      bigquery_dataset_location,
      bigquery_dataset_id
    )

    :ets.new(source_id, [:named_table, :ordered_set, :public])

    load_init_log_message(source_id, bigquery_project_id)

    rls = %{
      rls
      | bigquery_project_id: bigquery_project_id,
        bigquery_dataset_id: bigquery_dataset_id
    }

    children = [
      {RCS, rls},
      {EmailNotificationServer, rls},
      {TextNotificationServer, rls},
      {WebhookNotificationServer, rls},
      {SlackHookServer, rls},
      {Buffer, rls},
      {Schema, rls},
      {Pipeline, rls},
      {SearchQueryExecutor, rls}
    ]

    Supervisor.start_link(children, strategy: :one_for_all)

    Logger.info("RecentLogsServer started: #{source_id}")
    {:noreply, rls}
  end

  def handle_cast({:push, source_id, %LE{ingested_at: inj_at, sys_uint: sys_uint} = le}, state) do
    timestamp = inj_at |> Timex.to_datetime() |> DateTime.to_unix(:microsecond)
    :ets.insert(source_id, {{timestamp, sys_uint, 0}, le})
    {:noreply, state}
  end

  def handle_info({:stop_please, reason}, state) do
    {:stop, reason, state}
  end

  def handle_info(:broadcast, state) do
    if Source.Data.get_ets_count(state.source_id) > 0 do
      {:ok, total_cluster_inserts} = broadcast_count(state)
      broadcast()
      {:noreply, %{state | total_cluster_inserts: total_cluster_inserts}}
    else
      broadcast()
      {:noreply, state}
    end
  end

  def handle_info(:prune, %__MODULE__{source_id: source_id} = state) do
    count = Data.get_ets_count(source_id)

    case count > 100 do
      true ->
        for _log <- 101..count do
          log = :ets.first(source_id)

          if :ets.delete(source_id, log) == true do
            Counters.decriment(source_id)
          end
        end

        prune()
        {:noreply, state}

      false ->
        prune()
        {:noreply, state}
    end
  end

  def terminate(reason, %__MODULE__{} = state) do
    # Do Shutdown Stuff
    Logger.info("Going Down: #{state.source_id}")
    reason
  end

  ## Private Functions
  defp broadcast_count(state) do
    inserts = Tracker.Cache.get_cluster_inserts(state.source_id)

    payload = %{log_count: inserts, source_token: state.source_id}

    if inserts > state.total_cluster_inserts do
      Source.ChannelTopics.broadcast_log_count(payload)
    end

    {:ok, inserts}
  end

  defp load_init_log_message(source_id, _bigquery_project_id) do
    message =
      "Initialized on node #{Node.self()}. Waiting for new events. Send some logs, then try to explore & search!"

    log_event = LE.make(%{"message" => message}, %{source: %Source{token: source_id}})
    push(source_id, log_event)

    Source.ChannelTopics.broadcast_new(log_event)
  end

  defp prune() do
    Process.send_after(self(), :prune, @prune_timer)
  end

  defp broadcast() do
    Process.send_after(self(), :broadcast, @broadcast_every)
  end
end
