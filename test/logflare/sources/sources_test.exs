defmodule Logflare.SourcesTest do
  @moduledoc false
  use Logflare.DataCase
  import Logflare.DummyFactory
  alias Logflare.Sources
  alias Logflare.Google.BigQuery
  alias Logflare.Google.BigQuery.GenUtils
  alias GoogleApi.BigQuery.V2.Model.TableSchema, as: TS
  alias GoogleApi.BigQuery.V2.Model.TableFieldSchema, as: TFS

  setup do
    u = insert(:user, email: System.get_env("LOGFLARE_TEST_USER_WITH_SET_IAM"))
    s = insert(:source, token: Faker.UUID.v4(), rules: [], user_id: u.id)

    {:ok, sources: [s], users: [u]}
  end

  describe "Sources" do
    test "get_bq_schema/1", %{sources: [s | _], users: [u | _]} do
      source_id = s.token

      %{
        bigquery_table_ttl: bigquery_table_ttl,
        bigquery_dataset_location: bigquery_dataset_location,
        bigquery_project_id: bigquery_project_id,
        bigquery_dataset_id: bigquery_dataset_id
      } = GenUtils.get_bq_user_info(source_id)

      BigQuery.init_table!(
        u.id,
        source_id,
        bigquery_project_id,
        bigquery_table_ttl,
        bigquery_dataset_location,
        bigquery_dataset_id
      )

      schema = %TS{
        fields: [
          %TFS{
            description: nil,
            fields: nil,
            mode: "REQUIRED",
            name: "timestamp",
            type: "TIMESTAMP"
          },
          %TFS{
            description: nil,
            fields: nil,
            mode: "NULLABLE",
            name: "event_message",
            type: "STRING"
          },
          %TFS{
            description: nil,
            fields: [
              %TFS{
                description: nil,
                mode: "NULLABLE",
                name: "string1",
                type: "STRING",
                fields: nil
              }
            ],
            mode: "NULLABLE",
            name: "metadata",
            type: "RECORD"
          }
        ]
      }

      assert {:ok, _} =
               BigQuery.patch_table(source_id, schema, bigquery_dataset_id, bigquery_project_id)

      {:ok, left_schema} = Sources.get_bq_schema(s)
      assert left_schema == schema
    end
  end
end
