defmodule Logflare.Validator.BigQuerySchemaChangeTest do
  @moduledoc false
  use Logflare.DataCase
  use Placebo

  import Logflare.Logs.Validators.BigQuerySchemaChange

  alias Logflare.LogEvent, as: LE
  alias Logflare.Source.BigQuery.SchemaBuilder
  alias Logflare.Google.BigQuery.SchemaFactory
  alias Logflare.DummyFactory
  alias Logflare.Sources

  describe "bigquery schema change validation" do
    test "validate/1 returns :ok with no metadata in BQ schema" do
      u1 = DummyFactory.insert(:user)
      s1 = DummyFactory.insert(:source, user_id: u1.id)
      s1 = Sources.get_by(id: s1.id)
      schema = SchemaBuilder.initial_table_schema()
      allow Sources.Cache.get_bq_schema(s1), return: schema

      le =
        LE.make(
          %{
            "message" => "valid_test_message",
            "metadata" => %{
              "user" => %{
                "name" => "name one"
              }
            }
          },
          %{source: s1}
        )

      assert validate(le) === :ok
    end

    test "correctly creates a typemap from schema" do
      assert :schema
             |> SchemaFactory.build(variant: :third)
             |> to_typemap(from: :bigquery_schema) == typemap_for_third()
    end

    test "correctly builds a typemap from metadata" do
      assert :metadata
             |> SchemaFactory.build(variant: :third)
             |> to_typemap() == typemap_for_third().metadata.fields
    end

    test "valid? returns true for correct metadata and schema" do
      schema = SchemaFactory.build(:schema, variant: :third)
      metadata = SchemaFactory.build(:metadata, variant: :third)

      assert valid?(metadata, schema)
    end

    test "valid? returns false for various changed nested field types" do
      schema = SchemaFactory.build(:schema, variant: :third)

      event = SchemaFactory.build(:metadata, variant: :third)

      metadata =
        event
        |> put_in(~w[user address city], 1000)

      metadata2 =
        event
        |> put_in(~w[user vip], :not_boolean_atom)

      metadata3 =
        event
        |> put_in(~w[ip_address], %{"field" => 1})

      refute valid?(metadata, schema)
      refute valid?(metadata2, schema)
      refute valid?(metadata3, schema)
    end
  end

  def typemap_for_third() do
    %{
      timestamp: %{t: :datetime},
      event_message: %{t: :string},
      metadata: %{
        t: :map,
        fields: %{
          datacenter: %{t: :string},
          ip_address: %{t: :string},
          request_method: %{t: :string},
          user: %{
            t: :map,
            fields: %{
              browser: %{t: :string},
              id: %{t: :integer},
              vip: %{t: :boolean},
              company: %{t: :string},
              login_count: %{t: :integer},
              address: %{
                t: :map,
                fields: %{
                  street: %{t: :string},
                  city: %{t: :string},
                  st: %{t: :string}
                }
              }
            }
          }
        }
      }
    }
  end
end
