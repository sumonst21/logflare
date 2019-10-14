defmodule Logflare.Cluster.RedisTest do
  @moduledoc false
  use Logflare.DataCase
  alias Logflare.Sources.ClusterStore
  alias Logflare.Source
  alias Logflare.Sources
  alias Logflare.Redix, as: LR
  import Logflare.DummyFactory

  describe "cluster" do
    @describetag :skip
    test "source store get, increment, reset" do
      nodes =
        LocalCluster.start_nodes(:spawn, 3,
          files: [
            __ENV__.file
          ]
        )

      [node1, node2, node3] = nodes

      assert Node.ping(node1) == :pong
      assert Node.ping(node2) == :pong
      assert Node.ping(node3) == :pong

      source = %Source{token: "test-token"}

      caller = self()

      Node.spawn(node1, fn ->
        source = insert(:source)
        source = Sources.get_by(token: source.token)
        send(caller, source)
        ClusterStore.increment_counters(source)
      end)

      source =
        receive do
          msg -> msg
        end

      IO.inspect(source)

      Node.spawn(node2, fn ->
        ClusterStore.increment_counters(source)
      end)

      Node.spawn(node3, fn ->
        ClusterStore.increment_counters(source)
      end)
    end

    Process.sleep(1000)
    LR.keys() |> IO.inspect()
    # assert {:ok, "3"} = ClusterStore.get_source_last_rate(source.token, period: :minute)
  end
end
