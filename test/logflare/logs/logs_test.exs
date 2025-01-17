defmodule Logflare.LogsTest do
  @moduledoc false
  use Logflare.DataCase
  use Placebo
  import Logflare.DummyFactory
  alias Logflare.Logs
  alias Logflare.{SystemMetrics, Sources}
  alias Logflare.Source.{BigQuery.Buffer, RecentLogsServer}
  alias Logflare.Google.BigQuery
  alias Logflare.Google.BigQuery.{Query, GenUtils}
  alias Logflare.Sources.Counters
  @test_dataset_location "us-east4"

  setup do
    u = insert(:user)
    [sink1, sink2] = insert_list(2, :source, user_id: u.id)
    rule1 = build(:rule, sink: sink1.token, regex: "pattern2")
    rule2 = build(:rule, sink: sink2.token, regex: "pattern3")
    s1 = insert(:source, token: Faker.UUID.v4(), rules: [rule1, rule2], user_id: u.id)
    s1 = Sources.get_by(token: s1.token)
    SystemMetrics.start_link()
    Counters.start_link()
    {:ok, sources: [s1], sinks: [sink1, sink2]}
  end

  describe "log event ingest" do
    setup :with_iam_create_auth

    @tag :skip
    test "succeeds for floats", %{sources: [s]} do
      conn = GenUtils.get_conn()
      project_id = GenUtils.get_project_id(s.token)
      dataset_id = "test_dataset_#{s.user.id}"

      assert {:ok, _} =
               BigQuery.create_dataset(
                 "#{s.user_id}",
                 dataset_id,
                 @test_dataset_location,
                 project_id
               )

      assert {:ok, table} = BigQuery.create_table(s.token, dataset_id, project_id, 300_000)

      table_id = table.id |> String.replace(":", ".")
      sql = "SELECT * FROM `#{table_id}`"

      Logs.ingest_logs([%{"message" => "test", "metadata" => %{"float" => 0.001}}], s)
      Process.sleep(5_000)
      {:ok, response} = Query.query(conn, project_id, sql)
      assert response.rows == [%{"log_message" => "test", "metadata" => %{"float" => 0.001}}]
    end
  end

  def with_iam_create_auth(_) do
    u = insert(:user, email: System.get_env("LOGFLARE_TEST_USER_WITH_SET_IAM"))
    s1 = insert(:source, user_id: u.id)
    s1 = Sources.get_by(id: s1.id)
    {:ok, sources: [s1], users: [u]}
  end

  describe "log event ingest for source with rules" do
    test "sink source routing", %{sources: [s1 | _], sinks: [sink1, sink2 | _]} do
      allow RecentLogsServer.push(any(), any()), return: :ok
      allow Buffer.push(any(), any()), return: :ok
      allow Sources.Counters.incriment(any()), return: {:ok, 1}
      allow SystemMetrics.AllLogsLogged.incriment(any()), return: :ok
      allow Counters.get_total_inserts(any()), return: {:ok, 1}

      log_params_batch = [
        %{"message" => "pattern"},
        %{"message" => "pattern2"},
        %{"message" => "pattern3"}
      ]

      assert Logs.ingest_logs(log_params_batch, s1) == :ok

      # Original source
      assert_called RecentLogsServer.push(s1.token, any()), times(3)
      assert_called Sources.Counters.incriment(s1.token), times(3)
      assert_called Sources.Counters.get_total_inserts(s1.token), times(3)
      assert_called Buffer.push("#{s1.token}", any()), times(3)

      # Sink 1
      assert_called RecentLogsServer.push(
                      sink1.token,
                      is(fn le -> le.body.message === "pattern2" end)
                    ),
                    once()

      assert_called Sources.Counters.incriment(sink1.token), once()
      assert_called Sources.Counters.get_total_inserts(sink2.token), once()

      assert_called Buffer.push(
                      "#{sink1.token}",
                      is(fn le -> le.body.message === "pattern2" end)
                    ),
                    once()

      # Sink 2

      assert_called RecentLogsServer.push(
                      sink2.token,
                      is(fn le -> le.body.message === "pattern3" end)
                    ),
                    once()

      assert_called Sources.Counters.incriment(sink2.token), once()
      assert_called Sources.Counters.get_total_inserts(sink2.token), once()

      assert_called Buffer.push(
                      "#{sink2.token}",
                      is(fn le -> le.body.message === "pattern3" end)
                    ),
                    once()

      # All sources

      assert_called SystemMetrics.AllLogsLogged.incriment(any()), times(5)
    end

    test "sink routing is allowed for one depth level only" do
      allow RecentLogsServer.push(any(), any()), return: :ok
      allow Buffer.push(any(), any()), return: :ok
      allow Sources.Counters.incriment(any()), return: {:ok, 1}
      allow SystemMetrics.AllLogsLogged.incriment(any()), return: :ok
      allow Counters.get_total_inserts(any()), return: {:ok, 1}

      u = insert(:user)

      s1 = insert(:source, rules: [], user_id: u.id)

      first_sink = insert(:source, user_id: u.id)

      last_sink = insert(:source, user_id: u.id)

      _first_sink_rule =
        insert(:rule, sink: last_sink.token, regex: "test", source_id: first_sink.id)

      _s1rule1 = insert(:rule, sink: first_sink.token, regex: "test", source_id: s1.id)

      log_params_batch = [
        %{"message" => "test"}
      ]

      s1 = Sources.get_by(id: s1.id)

      assert Logs.ingest_logs(log_params_batch, s1) == :ok

      assert_called RecentLogsServer.push(s1.token, any()), once()
      assert_called Sources.Counters.incriment(s1.token), once()
      assert_called Sources.Counters.get_total_inserts(s1.token), once()
      assert_called Buffer.push("#{s1.token}", any()), once()

      assert_called RecentLogsServer.push(first_sink.token, any()), once()
      assert_called Sources.Counters.incriment(first_sink.token), once()
      assert_called Sources.Counters.get_total_inserts(first_sink.token), once()
      assert_called Buffer.push("#{first_sink.token}", any()), once()

      refute_called RecentLogsServer.push(last_sink.token, any()), once()
      refute_called Sources.Counters.incriment(last_sink.token), once()
      refute_called Sources.Counters.get_total_inserts(last_sink.token), once()
      refute_called Buffer.push("#{last_sink.token}", any()), once()
    end
  end
end
