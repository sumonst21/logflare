defmodule Logflare.Sources.ClusterStore do
  alias Logflare.Redix, as: LogflareRedix
  alias LogflareRedix, as: LR
  alias Logflare.RedixMulti, as: RMulti
  alias Logflare.Source
  alias Logflare.User
  alias Timex.Duration

  @second_counter_expiration_sec 60
  @minute_counter_expiration_sec Duration.from_minutes(10)
                                 |> Duration.to_seconds()
                                 |> round()
  @hour_counter_expiration_sec Duration.from_hours(24)
                               |> Duration.to_seconds()
                               |> round()
  @day_counter_expiration_sec Duration.from_hours(96)
                              |> Duration.to_seconds()
                              |> round()

  def increment_counters(%Source{} = source) do
    source_counters_keys = [
      {:second, @second_counter_expiration_sec},
      {:minute, @minute_counter_expiration_sec},
      {:hour, @hour_counter_expiration_sec},
      {:day, @day_counter_expiration_sec}
    ]

    user_counters_keys = [
      {:second, @second_counter_expiration_sec},
      {:minute, @minute_counter_expiration_sec},
      {:hour, @hour_counter_expiration_sec},
      {:day, @day_counter_expiration_sec}
    ]

    rmulti =
      RMulti.new()
      |> RMulti.client_reply(:on)
      |> RMulti.incr(all_sources_log_count())
      |> RMulti.incr(source_log_count(source))
      |> RMulti.incr(log_counter("all_logs", :second, Timex.now()), expire: 10)

    rmulti =
      Enum.reduce(
        source_counters_keys,
        rmulti,
        fn {period, expiration}, acc ->
          RMulti.incr(
            acc,
            log_counter(source, period, Timex.now()),
            expire: expiration
          )
        end
      )

    rmulti =
      Enum.reduce(
        user_counters_keys,
        rmulti,
        fn {period, expiration}, acc ->
          RMulti.incr(
            acc,
            log_counter(source.user, period, Timex.now()),
            expire: expiration
          )
        end
      )

    RMulti.run(rmulti)
  end

  # Global log total

  def all_sources_log_count() do
    "source::all_sources:total_log_count::v1"
  end

  def get_all_sources_log_count() do
    all_sources_log_count
    |> LR.get()
    |> handle_response(:integer)
  end

  def source_log_count(%Source{token: source_id}) do
    "source::#{source_id}::total_log_count::v1"
  end

  def get_sum_of_total_source_log_count() do
    with {:ok, keys} <- LR.scan_all_match("*source::*::total_log_count::v1"),
         {:ok, result} <- LR.multi_get(keys) do
      values = clean_and_parse(result)
      sum = Enum.sum(values)
      {:ok, sum}
    else
      {:error, :empty_keys_list} -> {:ok, 0}
      errtup -> errtup
    end
  end

  # Total log count

  def set_total_log_count(%Source{token: source_id} = _source, value) do
    key = "source::#{source_id}::total_log_count::v1"

    key
    |> LR.set(value, expire: 86_400)
    |> handle_response(:integer)
  end

  def get_total_log_count(%Source{token: source_id} = _source) do
    "source::#{source_id}::total_log_count::v1"
    |> LR.get()
    |> handle_response(:integer)
  end

  # Name generators

  defp log_counter(id, granularity, ts) when is_binary(id) and is_atom(granularity) do
    suffix = gen_suffix(granularity, ts)
    "global::#{id}::log_count::#{suffix}::v1"
  end

  defp log_counter(%Source{token: source_id}, granularity, ts) when is_atom(granularity) do
    suffix = gen_suffix(granularity, ts)
    "source::#{source_id}::log_count::#{suffix}::v1"
  end

  defp log_counter(%User{id: user_id}, granularity, ts) when is_atom(granularity) do
    suffix = gen_suffix(granularity, ts)
    "user::#{user_id}::log_count::#{suffix}::v1"
  end

  defp gen_suffix(granularity, ts) do
    ts =
      if is_integer(ts) do
        Timex.from_unix(ts)
      else
        ts
      end

    fmtstr =
      case granularity do
        :second -> "{Mshort}-{0D}-{h24}-{m}-{s}"
        :minute -> "{Mshort}-{0D}-{h24}-{m}-00"
        :hour -> "{Mshort}-{0D}-{h24}-00-00"
        :day -> "{Mshort}-{0D}-00-00-00"
      end

    tsfmt = Timex.format!(ts, fmtstr)
    "timestamp::#{granularity}::#{tsfmt}"
  end

  defp unix_ts_now() do
    NaiveDateTime.utc_now()
    |> Timex.to_unix()
  end

  # Max rate

  def get_max_rate(%Source{token: source_id} = _source) do
    "source::#{source_id}::max_rate::global::v1"
    |> LR.get()
    |> handle_response(:integer)
  end

  @expire 86_400
  def set_max_rate(%Source{token: source_id} = _source, value) do
    LR.set("source::#{source_id}::max_rate::global::v1", value, expire: @expire)
  end

  def set_max_rate(source_id, value) when is_atom(source_id) do
    LR.set("source::#{source_id}::max_rate::global::v1", value, expire: @expire)
  end

  # Avg rate

  def get_default_avg_rate(%Source{token: _source_id} = source) do
    t = Timex.now()

    result =
      source
      |> log_counter(:minute, unix_ts_now())
      |> LR.get()
      |> handle_response(:integer)

    elapsed_seconds = if t.second === 0, do: 1, else: t.second

    with {:ok, rate} <- result do
      {:ok, div(rate, elapsed_seconds)}
    else
      errtup -> errtup
    end
  end

  # Counters

  def get_prev_counter(source_or_user, period: period) do
    timex_period =
      case period do
        :second -> :seconds
        :minute -> :minutes
        :hour -> :hours
        :day -> :days
      end

    prev_ts = Timex.shift(Timex.now(), [{timex_period, -1}])

    source_or_user
    |> log_counter(period, prev_ts)
    |> LR.get()
    |> handle_response(:integer)
  end

  def get_current_counter(source_or_user, period: period) do
    source_or_user
    |> log_counter(period, unix_ts_now())
    |> LR.get()
    |> handle_response(:integer)
  end

  # Buffer counts

  def set_buffer_count(%Source{token: source_id} = _source, value) do
    key = "source::#{source_id}::buffer::#{Node.self()}::v1"
    LR.set(key, value, expire: 5)
  end

  def set_buffer_count(source_id, value) do
    key = "source::#{source_id}::buffer::#{Node.self()}::v1"
    LR.set(key, value, expire: 5)
  end

  def get_buffer_count(%Source{token: source_id} = _source) do
    with {:ok, keys} <- LR.scan_all_match("*source::#{source_id}::buffer::*"),
         {:ok, result} <- LR.multi_get(keys) do
      values = clean_and_parse(result)
      buffer = Enum.sum(values)
      {:ok, buffer}
    else
      {:error, :empty_keys_list} -> {:ok, 0}
      errtup -> errtup
    end
  end

  defp clean_and_parse(result) do
    result
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.to_integer/1)
  end

  def handle_response({:ok, "OK"}, :integer), do: :ok
  def handle_response({:ok, nil}, :integer), do: {:ok, 0}

  def handle_response({:ok, result}, :integer) when is_binary(result) do
    {:ok, String.to_integer(result)}
  end

  def handle_response({:error, error}, _) do
    {:error, error}
  end

  def handle_response(tup, :integer) do
    tup
  end
end
