defmodule Logflare.Sources.Cache do
  @moduledoc false
  import Cachex.Spec
  alias Logflare.{Sources, Source}
  @ttl 5_000

  @cache __MODULE__

  def child_spec(_) do
    %{
      id: :cachex_sources_cache,
      start: {
        Cachex,
        :start_link,
        [
          @cache,
          [expiration: expiration(default: @ttl)]
        ]
      }
    }
  end

  def get_bq_schema(%Source{token: token}) do
    Cachex.get!(@cache, {{:put_bq_schema, 1}, token})
  end

  def put_bq_schema(source_token, schema) do
    Cachex.put(@cache, {{:put_bq_schema, 1}, source_token}, schema, ttl: :timer.hours(24 * 365))
  end

  def get_by_and_preload(keyword), do: apply_repo_fun(__ENV__.function, [keyword])
  def get_by_id_and_preload(arg) when is_integer(arg), do: get_by_and_preload(id: arg)
  def get_by_id_and_preload(arg) when is_atom(arg), do: get_by_and_preload(token: arg)
  def get_by_name_and_preload(arg) when is_binary(arg), do: get_by_and_preload(name: arg)
  def get_by_pk_and_preload(arg), do: get_by_and_preload(id: arg)
  def get_by_public_token_and_preload(arg), do: get_by_and_preload(public_token: arg)

  def get_by(keyword), do: apply_repo_fun(__ENV__.function, [keyword])
  def get_by_id(arg) when is_integer(arg), do: get_by(id: arg)
  def get_by_id(arg) when is_atom(arg), do: get_by(token: arg)
  def get_by_name(arg) when is_binary(arg), do: get_by(name: arg)
  def get_by_pk(arg), do: get_by(id: arg)
  def get_by_public_token(arg), do: get_by(public_token: arg)

  def valid_source_token_param?(arg), do: apply_repo_fun(__ENV__.function, [arg])

  defp apply_repo_fun(arg1, arg2) do
    Logflare.ContextCache.apply_repo_fun(Sources, arg1, arg2)
  end
end
