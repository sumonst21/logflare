defmodule Logflare.SystemMetrics.AllLogsLogged do
  @moduledoc false
  use GenServer

  alias Logflare.Repo
  alias Logflare.SystemMetric
  alias Logflare.Redix, as: LfRedix
  alias Logflare.Sources.ClusterStore
  import Ecto.Query
  alias Logflare.SystemMetric
  alias Logflare.Repo

  require Logger

  @total_logs :total_logs_logged
  @table :system_counter
  @persist_every 60_000

  def start_link(init_args) do
    GenServer.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  def init(state) do
    # persist()

    {:ok, state, {:continue, :load_table_counts}}
  end

  def handle_continue(:load_table_counts, state) do
    all_logs_logged_pg =
      SystemMetric
      |> select([s], sum(s.all_logs_logged))
      |> Repo.one()

    {:ok, total_count} = ClusterStore.get_all_sources_log_count()

    if all_logs_logged_pg > total_count do
      :ok =
        ClusterStore.all_sources_log_count()
        |> LfRedix.set(all_logs_logged_pg)
    end

    {:noreply, state}
  end

  def handle_info(:persist, state) do
    persist()

    {:ok, log_count} = log_count(@total_logs)

    insert_or_update_node_metric(%{all_logs_logged: log_count, node: node_name()})

    {:noreply, state}
  end

  @spec log_count(atom()) :: {:ok, non_neg_integer}
  def log_count(@total_logs) do
    ClusterStore.get_all_sources_log_count()
  end

  ## Private Functions

  defp node_name() do
    Atom.to_string(node())
  end

  defp insert_or_update_node_metric(params) do
    case Repo.get_by(SystemMetric, node: node_name()) do
      nil ->
        changeset = SystemMetric.changeset(%SystemMetric{}, params)

        Repo.insert(changeset)

      metric ->
        changeset = SystemMetric.changeset(metric, params)

        Repo.update(changeset)
    end
  end

  defp persist() do
    Process.send_after(self(), :persist, @persist_every)
  end
end
