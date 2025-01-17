defmodule LogflareWeb.Source.SearchLV.SearchParams do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :tailing?, :boolean
    field :querystring, :string
  end

  def new(params) do
    %__MODULE__{}
    |> cast(params, __schema__(:fields))
    |> Map.get(:changes)
  end
end
