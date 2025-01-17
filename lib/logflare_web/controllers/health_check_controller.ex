defmodule LogflareWeb.HealthCheckController do
  use LogflareWeb, :controller

  alias Logflare.Cluster

  def check(conn, params) do
    nodes = Cluster.Utils.node_list_all()
    proc_count = Process.list() |> Enum.count()

    response =
      %{
        status: :ok,
        proc_count: proc_count,
        this_node: Node.self(),
        nodes: nodes,
        nodes_count: Enum.count(nodes)
      }
      |> Jason.encode!()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, response)
  end
end
