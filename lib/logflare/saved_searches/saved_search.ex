defmodule Logflare.SavedSearch do
  use Ecto.Schema
  alias Logflare.Source
  import Ecto.Changeset

  schema "saved_searches" do
    field :querystring, :string
    belongs_to :source, Source

    timestamps()
  end

  def changeset(saved_search, attrs \\ %{}) do
    saved_search
    |> cast(attrs, [:querystring])
    |> validate_required([:querystring])
    |> unique_constraint(:querystring, name: :saved_searches_querystring_source_id_index)
  end
end
