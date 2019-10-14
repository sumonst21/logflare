defmodule Logflare.RedixMulti do
  alias Logflare.Redix, as: LR
  defstruct commands: [], client_reply: :on

  def new() do
    %__MODULE__{}
  end

  def set(rmulti, key, value, options \\ []) do
    Map.update!(rmulti, :commands, &[["SET", key, value] | &1])
  end

  def client_reply(rmulti, value) when value in ~w(on off skip)a do
    Map.put(rmulti, :client_reply, value)
  end

  def incr(rmulti, key, opts \\ []) do
    amount = opts[:amount] || 1

    new_commands =
      if amount === 1 do
        [["INCR", key]]
      else
        [["INCRBY", key, amount]]
      end

    expire = opts[:expire]

    new_commands =
      if expire do
        new_commands ++ [["EXPIRE", key, expire]]
      else
        new_commands
      end

    Map.update!(rmulti, :commands, &(&1 ++ new_commands))
  end

  def get() do
  end

  def run(rmulti) do
    result =
      case rmulti.client_reply do
        :on ->
          LR.pipeline(rmulti.commands)

        :skip ->
          LR.noreply_pipeline(rmulti.commands)
      end

    with {:ok, result} <- result,
         {:ok, response} <- process_multi_response(result) do
      {:ok, response}
    else
      errtup -> errtup
    end
  end

  def process_multi_response(response) when is_list(response) do
    errors =
      response
      |> Enum.filter(fn
        %Redix.Error{} -> true
        _ -> false
      end)

    if length(errors) > 0 do
      {:error, %{errors: errors}}
    else
      {:ok, response}
    end
  end
end
