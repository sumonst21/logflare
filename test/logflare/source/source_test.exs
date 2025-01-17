defmodule Logflare.SourceTest do
  @moduledoc false
  alias Logflare.{Source, Sources}
  use Logflare.DataCase

  describe "Source" do
    test "generate_bq_table_id/1" do
      u = insert(:user)
      s = insert(:source, token: "44a6851a-9a6f-49ee-822f-12c6f17bedee", rules: [], user_id: u.id)
      s = Sources.get_by(id: s.id)

      assert Source.generate_bq_table_id(s) ==
               "`logflare-dev-238720`.#{s.user_id}_test.44a6851a_9a6f_49ee_822f_12c6f17bedee"
    end

    test "generate_bq_table_id/1 with custom bigquery_dataset_id" do
      u = insert(:user, bigquery_dataset_id: "test_custom_dataset_1")
      s = insert(:source, token: "44a6851a-9a6f-49ee-822f-12c6f17bedee", rules: [], user_id: u.id)
      s = Sources.get_by(id: s.id)

      assert s.bq_table_id ==
               "`logflare-dev-238720`.test_custom_dataset_1.44a6851a_9a6f_49ee_822f_12c6f17bedee"
    end
  end
end
