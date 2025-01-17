defmodule LogflareWeb.SourceControllerTest do
  @moduledoc false
  import LogflareWeb.Router.Helpers
  use LogflareWeb.ConnCase
  use Placebo

  alias Logflare.{Sources, Repo, LogEvent}
  alias Logflare.Logs.RejectedLogEvents
  import Logflare.DummyFactory

  setup do
    u1 = insert(:user)
    u2 = insert(:user)

    s1 = insert(:source, public_token: Faker.String.base64(16), user_id: u1.id)
    s2 = insert(:source, user_id: u1.id)
    s3 = insert(:source, user_id: u2.id)

    users = Repo.preload([u1, u2], :sources)

    sources = [s1, s2, s3]

    {:ok, users: users, sources: sources}
  end

  describe "dashboard" do
    setup [:assert_caches_not_called]

    test "renders dashboard", %{conn: conn, users: [u1, _u2], sources: [s1, _s2 | _]} do
      conn =
        conn
        |> login_user(u1)
        |> get("/dashboard")

      dash_sources = Enum.map(conn.assigns.sources, & &1.metrics)
      dash_source_1 = hd(dash_sources)

      source_stat_fields = ~w[avg buffer inserts latest max rate id]a

      assert is_list(dash_sources)
      assert source_stat_fields -- Map.keys(dash_source_1) === []
      assert hd(conn.assigns.sources).id == s1.id
      assert hd(conn.assigns.sources).token == s1.token
      assert html_response(conn, 200) =~ "dashboard"
      refute_called Sources.Cache.get_by(any()), once()
    end

    test "renders rejected logs page", %{conn: conn, users: [u1, _u2], sources: [s1, _s2 | _]} do
      RejectedLogEvents.ingest(%LogEvent{
        validation_error: Logflare.Logs.Validators.EqDeepFieldTypes.message(),
        params: %{"no_log_entry" => true, "timestamp" => ""},
        source: s1,
        valid?: false,
        ingested_at: NaiveDateTime.utc_now()
      })

      conn =
        conn
        |> login_user(u1)
        |> get("/sources/#{s1.id}/rejected")

      assert html_response(conn, 200) =~ "dashboard"

      assert [
               %LogEvent{
                 validation_error:
                   "Metadata validation error: values with the same field path must have the same type.",
                 params: %{"no_log_entry" => true, "timestamp" => ""},
                 ingested_at: _
               }
             ] = conn.assigns.logs

      refute_called Sources.Cache.get_by(any()), once()
    end
  end

  describe "update" do
    setup [:assert_caches_not_called]

    test "returns 200 with valid params", %{conn: conn, users: [u1, _u2], sources: [s1, _s2 | _]} do
      new_name = Faker.String.base64()

      params = %{
        "id" => s1.id,
        "source" => %{
          "favorite" => true,
          "name" => new_name
        }
      }

      conn =
        conn
        |> login_user(u1)
        |> patch("/sources/#{s1.id}", params)

      s1_new = Sources.get_by(token: s1.token)

      assert html_response(conn, 302) =~ "redirected"
      assert get_flash(conn, :info) == "Source updated!"
      assert s1_new.name == new_name
      assert s1_new.favorite == true

      conn =
        conn
        |> recycle()
        |> login_user(u1)
        |> get(source_path(conn, :edit, s1.id))

      assert conn.assigns.source.name == new_name
      refute_called Sources.Cache.get_by(any()), once()
    end

    test "returns 406 with invalid params", %{
      conn: conn,
      users: [u1, _u2],
      sources: [s1, _s2 | _]
    } do
      new_name = "this should never be inserted"

      params = %{
        "id" => s1.id,
        "source" => %{
          "favorite" => 1,
          "name" => new_name
        }
      }

      conn =
        conn
        |> login_user(u1)
        |> patch("/sources/#{s1.id}", params)

      s1_new = Sources.get_by(token: s1.token)

      assert s1_new.name != new_name
      assert get_flash(conn, :error) == "Something went wrong!"
      assert html_response(conn, 406) =~ "Source Name"
      refute_called Sources.Cache.get_by(any()), once()
    end

    test "returns 200 but doesn't change restricted params", %{
      conn: conn,
      users: [u1, _u2],
      sources: [s1, _s2 | _]
    } do
      nope_token = Faker.UUID.v4()
      nope_api_quota = 1337
      nope_user_id = 1

      params = %{
        "id" => s1.id,
        "source" => %{
          "name" => s1.name,
          "token" => nope_token,
          "api_quota" => nope_api_quota,
          "user_id" => nope_user_id
        }
      }

      conn =
        conn
        |> login_user(u1)
        |> patch("/sources/#{s1.id}", params)

      s1_new = Sources.get_by(id: s1.id)

      refute conn.assigns[:changeset]
      refute s1_new.token == nope_token
      refute s1_new.api_quota == nope_api_quota
      refute s1_new.user_id == nope_user_id
      assert redirected_to(conn, 302) =~ source_path(conn, :edit, s1.id)
      refute_called Sources.Cache.get_by(any()), once()
    end

    test "returns 403 when user is not an owner of source", %{
      conn: conn,
      users: [u1, _u2],
      sources: [s1, _s2, u2s1 | _]
    } do
      conn =
        conn
        |> login_user(u1)
        |> patch(
          "/sources/#{u2s1.id}",
          %{
            "source" => %{
              "name" => "it's mine now!"
            }
          }
        )

      s1_new = Sources.get_by(id: s1.id)

      refute s1_new.name === "it's mine now!"
      assert conn.halted === true
      assert get_flash(conn, :error) =~ "That's not yours!"
      assert redirected_to(conn, 403) =~ marketing_path(conn, :index)
      refute_called Sources.Cache.get_by(any()), once()
    end
  end

  describe "show" do
    setup [:assert_caches_not_called]

    test "renders source for a logged in user", %{conn: conn, users: [u1 | _], sources: [s1 | _]} do
      conn =
        conn
        |> login_user(u1)
        |> get(source_path(conn, :show, s1.id), %{
          "source" => %{
            "name" => Faker.Name.name()
          }
        })

      assert html_response(conn, 200) =~ s1.name
      refute_called Sources.Cache.get_by(any()), once()
    end

    test "returns 403 for a source not owned by the user", %{
      conn: conn,
      users: [_u1, u2 | _],
      sources: [s1 | _]
    } do
      conn =
        conn
        |> login_user(u2)
        |> get(source_path(conn, :show, s1.id))

      assert redirected_to(conn, 403) === "/"
      refute_called Sources.Cache.get_by(any()), once()
    end
  end

  describe "create" do
    setup [:assert_caches_not_called]

    test "returns 200 with valid params", %{conn: conn, users: [u1 | _]} do
      conn =
        conn
        |> login_user(u1)
        |> post("/sources", %{
          "source" => %{
            "name" => Faker.Name.name(),
            "token" => Faker.UUID.v4()
          }
        })

      refute conn.assigns[:changeset]
      assert redirected_to(conn, 302) === source_path(conn, :dashboard)
      refute_called Sources.Cache.get_by(any()), once()
    end

    test "renders error flash and redirects for missing token", %{conn: conn, users: [u1 | _]} do
      conn =
        conn
        |> login_user(u1)
        |> post("/sources", %{
          "source" => %{
            "name" => Faker.Name.name()
          }
        })

      assert conn.assigns[:changeset].errors === [
               token: {"can't be blank", [validation: :required]}
             ]

      assert redirected_to(conn, 302) === source_path(conn, :new)
      refute_called Sources.Cache.get_by(any()), once()
    end

    test "renders error flash for source with empty name", %{conn: conn, users: [u1 | _]} do
      conn =
        conn
        |> login_user(u1)
        |> post("/sources", %{
          "source" => %{
            "name" => "",
            "token" => Faker.UUID.v4()
          }
        })

      assert conn.assigns[:changeset].errors === [
               name: {"can't be blank", [validation: :required]}
             ]

      assert redirected_to(conn, 302) === source_path(conn, :new)
      refute_called Sources.Cache.get_by(any()), once()
    end
  end

  describe "edit" do
    setup [:assert_caches_not_called]

    test "returns 200 with new user-provided params", %{conn: _conn} do
    end
  end

  describe "favorite" do
    setup [:assert_caches_not_called]

    test "returns 200 flipping the value", %{conn: conn, users: [u1 | _], sources: [s1 | _]} do
      conn =
        conn
        |> login_user(u1)
        |> get(source_path(conn, :favorite, Integer.to_string(s1.id)))

      new_s1 = Sources.get_by(id: s1.id)

      assert get_flash(conn, :info) == "Source updated!"
      assert redirected_to(conn, 302) =~ source_path(conn, :dashboard)
      assert new_s1.favorite == not s1.favorite
      refute_called Sources.Cache.get_by(any()), once()
    end
  end

  describe "public" do
    test "shows a source page", %{conn: conn, sources: [s1 | _]} do
      conn =
        conn
        |> get(source_path(conn, :public, s1.public_token))

      assert html_response(conn, 200) =~ s1.name
    end
  end

  def login_user(conn, u) do
    conn
    |> assign(:user, u)
  end

  def assert_caches_not_called(_) do
    allow Sources.Cache.get_by(any()), return: :should_not_happen
    :ok
  end
end
