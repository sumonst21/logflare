defmodule Logflare.RedixMulti do
  alias Logflare.Redix, as: LR
  defstruct commands: []

  def new() do
    %__MODULE__{}
  end

  def set(rmulti, key, value, options \\ []) do
    Map.update!(rmulti, :commands, &[["SET", key, value] | &1])
  end

  def increment(rmulti, key, opts \\ []) do
    amount = opts[:amount] || 1
    new_commands = [["INCREMENT", key, amount]]
    expire = opts[:expire]

    new_commands =
      if expire do
        new_commands ++ [["EXPIRE", expire]]
      else
        new_commands
      end

    Map.update!(rmulti, :commands, &(&1 ++ new_commands))
  end

  def get() do
  end

  def run(rmulti) do
    rmulti.commands
    |> LR.pipeline()
  end
end
