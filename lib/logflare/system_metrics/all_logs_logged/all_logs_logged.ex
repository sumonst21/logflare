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
    {:ok, state, {:continue, :load_table_counts}}
  end

  def handle_continue(:load_table_counts, state) do
    all_logs_logged_pg =
      SystemMetric
      |> select([s], sum(s.all_logs_logged))
      |> Repo.one()
      |> Decimal.to_integer()

    {:ok, total_count} = ClusterStore.get_all_sources_log_count()

    if all_logs_logged_pg > total_count do
      :ok =
        ClusterStore.all_sources_log_count()
        |> LfRedix.set(all_logs_logged_pg)
    end

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
end
