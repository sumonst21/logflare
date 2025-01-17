defmodule Logflare.Source.BigQuery.SchemaBuilder do
  @moduledoc false
  use Publicist
  require Logger
  alias GoogleApi.BigQuery.V2.Model
  alias Model.TableFieldSchema, as: TFS

  @doc """
  Builds table schema from event metadata and prev schema.

  Arguments:

  * metadata: event metadata
  * old_schema: existing Model.TableFieldSchema,

  Accepts both metadata map and metadata map wrapped in a list.
  """
  @spec build_table_schema([map], TFS.t()) :: TFS.t()
  def build_table_schema([metadata], old_schema) do
    build_table_schema(metadata, old_schema)
  end

  @spec build_table_schema(map, TFS.t()) :: TFS.t()
  def build_table_schema(metadata, %{fields: old_fields}) do
    old_metadata_schema = Enum.find(old_fields, &(&1.name == "metadata")) || %{}

    metadata_field = build_metadata_fields_schemas(metadata, old_metadata_schema)

    initial_table_schema()
    |> Map.update!(:fields, &Enum.concat(&1, [metadata_field]))
    |> deep_sort_by_fields_name()
  end

  def initial_table_schema() do
    %Model.TableSchema{
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
        }
      ]
    }
  end

  @spec build_metadata_fields_schemas(map, TFS.t()) :: TFS.t()
  defp build_metadata_fields_schemas(metadata, old_metadata_schema) do
    new_metadata_schema = build_fields_schemas({"metadata", metadata})

    old_metadata_schema
    # DeepMerge resolver is implemented for Model.TableFieldSchema structs
    |> DeepMerge.deep_merge(new_metadata_schema)
  end

  defp build_fields_schemas({params_key, params_val}) when is_map(params_val) do
    %TFS{
      description: nil,
      mode: "REPEATED",
      name: params_key,
      type: "RECORD",
      fields: Enum.map(params_val, &build_fields_schemas/1)
    }
  end

  defp build_fields_schemas(maps) when is_list(maps) do
    maps
    |> Enum.reduce(%{}, &DeepMerge.deep_merge/2)
    |> Enum.map(&build_fields_schemas/1)
  end

  defp build_fields_schemas({params_key, params_value}) do
    case Logflare.BigQuery.SchemaTypes.to_schema_type(params_value) do
      "ARRAY" ->
        case hd(params_value) do
          x when is_map(x) ->
            %TFS{
              name: params_key,
              type: "RECORD",
              mode: "REPEATED",
              fields: build_fields_schemas(params_value)
            }

          x when is_binary(x) ->
            %TFS{
              name: params_key,
              type: "STRING",
              mode: "NULLABLE"
            }
        end

      type ->
        %TFS{
          name: params_key,
          type: type,
          mode: "NULLABLE"
        }
    end
  end

  @spec deep_sort_by_fields_name(TFS.t()) :: TFS.t()
  def deep_sort_by_fields_name(%{fields: nil} = schema), do: schema

  def deep_sort_by_fields_name(%{fields: fields} = schema) when is_list(fields) do
    sorted_fields =
      fields
      |> Enum.sort_by(& &1.name)
      |> Enum.map(&deep_sort_by_fields_name/1)

    %{schema | fields: sorted_fields}
  end

  defimpl DeepMerge.Resolver, for: Model.TableFieldSchema do
    @doc """
    Implements merge for schema key conflicts.
    Overwrites fields schemas that are present BOTH in old and new TFS structs and keeps fields schemas present ONLY in old.
    """

    @spec resolve(TFS.t(), TFS.t(), fun) :: TFS.t()
    def resolve(old, new, _standard_resolver) do
      resolve(old, new)
    end

    @spec resolve(TFS.t(), TFS.t()) :: TFS.t()
    def resolve(
          %TFS{fields: old_fields},
          %TFS{fields: new_fields} = new_tfs
        )
        when is_list(old_fields)
        when is_list(new_fields) do
      # collect all names for new fields schemas
      new_fields_names = Enum.map(new_fields, & &1.name)

      # filter field schemas that are present only in old table field schema
      uniq_old_fs = for fs <- old_fields, fs.name not in new_fields_names, do: fs

      %{new_tfs | fields: resolve_list(old_fields, new_fields) ++ uniq_old_fs}
    end

    def resolve(_old, %TFS{} = new) do
      new
    end

    @spec resolve_list(list(TFS.t()), list(TFS.t())) :: list(TFS.t())
    def resolve_list(old_fields, new_fields)
        when is_list(old_fields)
        when is_list(new_fields) do
      for %TFS{} = new_field <- new_fields do
        old_fields
        |> maybe_find_with_name(new_field)
        |> resolve(new_field)
      end
    end

    @spec maybe_find_with_name(list(TFS.t()), TFS.t()) :: TFS.t() | nil
    def maybe_find_with_name(enumerable, %TFS{name: name}) do
      Enum.find(enumerable, &(&1.name === name))
    end
  end
end
