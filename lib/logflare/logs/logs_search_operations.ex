defmodule Logflare.Logs.SearchOperations do
  @moduledoc false
  alias Logflare.Google.BigQuery.{GenUtils, SchemaUtils}
  alias Logflare.{Source, Sources, EctoQueryBQ}
  alias Logflare.Logs.Search.Parser
  import Ecto.Query

  alias GoogleApi.BigQuery.V2.Api
  alias GoogleApi.BigQuery.V2.Model.QueryRequest

  use Logflare.GenDecorators
  @decorate_all pass_through_on_error_field()


  @default_limit 100
  @default_processed_bytes_limit 10_000_000_000



  # Note that this is only a timeout for the request, not the query.
  # If the query takes longer to run than the timeout value, the call returns without any results and with the 'jobComplete' flag set to false.
  @query_request_timeout 60_000

  defmodule SearchOperation do
    @moduledoc """
    Logs search options and result
    """
    use TypedStruct

    typedstruct do
      field :source, Source.t()
      field :querystring, String.t()
      field :query, Ecto.Query.t()
      field :query_result, term()
      field :sql_params, {term(), term()}
      field :tailing?, boolean
      field :tailing_initial?, boolean
      field :rows, [map()]
      field :pathvalops, [map()]
      field :error, term()
      field :stats, :map
    end
  end

  alias SearchOperation, as: SO

  def do_query(%SO{} = so) do
    %SO{source: %Source{token: source_id}} = so
    project_id = GenUtils.get_project_id(source_id)
    conn = GenUtils.get_conn()

    {sql, params} = so.sql_params

    query_request = %QueryRequest{
      query: sql,
      useLegacySql: false,
      useQueryCache: true,
      parameterMode: "POSITIONAL",
      queryParameters: params,
      dryRun: false,
      timeoutMs: @query_request_timeout
    }

    dry_run = %{query_request | dryRun: true}

    result =
      Api.Jobs.bigquery_jobs_query(
        conn,
        project_id,
        body: dry_run
      )

    with {:ok, response} <- result,
         is_within_limit? =
           String.to_integer(response.totalBytesProcessed) <= @default_processed_bytes_limit,
         {:total_bytes_processed, true} <- {:total_bytes_processed, is_within_limit?} do
      Api.Jobs.bigquery_jobs_query(
        conn,
        project_id,
        body: query_request
      )
    else
      {:total_bytes_processed, false} ->
        {:error,
         "Query halted: total bytes processed for this query is expected to be larger than #{
           div(@default_processed_bytes_limit, 1_000_000_000)
         } GB"}

      errtup ->
        errtup
    end
    |> Utils.put_result_in(so, :query_result)
    |> prepare_query_result()
  end

  def prepare_query_result(%SO{} = so) do
    query_result =
      so.query_result
      |> Map.update(:totalBytesProcessed, 0, &Utils.maybe_string_to_integer/1)
      |> Map.update(:totalRows, 0, &Utils.maybe_string_to_integer/1)
      |> AtomicMap.convert(%{safe: false})

    %{so | query_result: query_result}
  end

  def order_by_default(%SO{} = so) do
    %{so | query: order_by(so.query, desc: :timestamp)}
  end

  def apply_limit_to_query(%SO{} = so) do
    %{so | query: limit(so.query, @default_limit)}
  end

  def put_stats(%SO{} = so) do
    stats =
      so.stats
      |> Map.merge(%{
        total_rows: so.query_result.total_rows,
        total_bytes_processed: so.query_result.total_bytes_processed
      })
      |> Map.put(
        :total_duration,
        System.monotonic_time(:millisecond) - so.stats.start_monotonic_time
      )

    %{so | stats: stats}
  end

  def process_query_result(%SO{} = so) do
    %{schema: schema, rows: rows} = so.query_result
    rows = SchemaUtils.merge_rows_with_schema(schema, rows)
    %{so | rows: rows}
  end

  def default_from(%SO{} = so) do
    %{so | query: from(so.source.bq_table_id)}
  end

  def apply_to_sql(%SO{} = so) do
    %{so | sql_params: EctoQueryBQ.SQL.to_sql(so.query)}
  end

  def apply_wheres(%SO{} = so) do
    %{so | query: EctoQueryBQ.where_nesteds(so.query, so.pathvalops)}
  end

  def parse_querystring(%SO{} = so) do
    schema =
      so.source
      |> Sources.Cache.get_bq_schema()

    so.querystring
    |> Parser.parse(schema)
    |> Utils.put_result_in(so, :pathvalops)
  end


  def partition_or_streaming(%SO{tailing?: true, tailing_initial?: true} = so) do
    query =
      where(
        so.query,
        [log],
        fragment(
          "TIMESTAMP_ADD(_PARTITIONTIME, INTERVAL 24 HOUR) > CURRENT_TIMESTAMP() OR _PARTITIONTIME IS NULL"
        )
      )

    so
    |> Map.put(:query, query)
    |> drop_timestamp_pathvalops
  end

  def partition_or_streaming(%SO{tailing?: true} = so) do
    so
    |> Map.update!(:query, &query_only_streaming_buffer/1)
    |> drop_timestamp_pathvalops
  end

  def partition_or_streaming(%SO{} = so), do: so

  def drop_timestamp_pathvalops(%SO{} = so) do
    %{so | pathvalops: Enum.reject(so.pathvalops, &(&1.path === "timestamp"))}
  end

  def query_only_streaming_buffer(q), do: where(q, [l], fragment("_PARTITIONTIME IS NULL"))

  def verify_path_in_schema(%SO{} = so) do
    flatmap =
      so.source
      |> Sources.Cache.get_bq_schema()
      |> Logflare.Logs.Validators.BigQuerySchemaChange.to_typemap()
      |> Iteraptor.to_flatmap()
      |> Enum.map(fn {k, v} -> {String.replace(k, ".fields", ""), v} end)
      |> Enum.map(fn {k, _} -> String.trim_trailing(k, ".t") end)

    result =
      Enum.reduce_while(so.pathvalops, :ok, fn %{path: path}, _ ->
        if path in flatmap do
          {:cont, :ok}
        else
          {:halt, {:error, "#{path} not present in source schema"}}
        end
      end)

    Utils.put_result_in(result, so)
  end

  def apply_local_timestamp_correction(%SO{} = so) do
    pathvalops =
      Enum.map(so.pathvalops, fn
        %{path: "timestamp", value: value} = pvo ->
          %{pvo | value: Timex.Timezone.convert(value, so.user_local_timezone)}
      end)

    %{so | pathvalops: pathvalops}
  end

  def apply_selects(%SO{} = so) do
    top_level_fields =
      so.source
      |> Sources.Cache.get_bq_schema()
      |> Logflare.Logs.Validators.BigQuerySchemaChange.to_typemap()
      |> Map.keys()

    %{so | query: select(so.query, ^top_level_fields)}
  end
end
