use Mix.Config

config :logflare, env: :dev

config :logflare, LogflareWeb.Endpoint,
  http: [port: 4000, transport_options: [max_connections: 16384, num_acceptors: 10]],
  url: [host: "dev.chasegranberry.net", scheme: "http"],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    node: [
      "node_modules/webpack/bin/webpack.js",
      "--mode",
      "development",
      "--watch-stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

config :logflare, LogflareWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{priv/gettext/.*(po)$},
      ~r{lib/logflare_web/views/.*(ex)$},
      ~r{lib/logflare_web/templates/.*(eex)$},
      ~r{lib/logflare_web/live/.*(ex)$}
    ]
  ]

config :logger, :console, format: "[$level] $message\n"

# config :logger,
#   level: :info,
#   backends: [LogflareLogger.HttpBackend]

config :logger,
  level: :debug

config :phoenix, :stacktrace_depth, 20

config :logflare, Logflare.Repo,
  username: "chasegranberry",
  password: "",
  database: "logtail_dev",
  hostname: "localhost",
  pool_size: 10,
  prepare: :unnamed

config :logflare, Logflare.Google,
  dataset_id_append: "_dev",
  project_number: "1023172132421",
  project_id: "logflare-dev-238720",
  service_account: "logflare-dev@logflare-dev-238720.iam.gserviceaccount.com",
  compute_engine_sa: "1023172132421-compute@developer.gserviceaccount.com",
  api_sa: "1023172132421@cloudservices.gserviceaccount.com",
  cloud_build_sa: "1023172132421@cloudbuild.gserviceaccount.com",
  gcp_cloud_build_sa: "service-1023172132421@gcp-sa-cloudbuild.iam.gserviceaccount.com",
  compute_system_iam_sa: "service-1023172132421@compute-system.iam.gserviceaccount.com",
  container_engine_robot_sa:
    "service-1023172132421@container-engine-robot.iam.gserviceaccount.com",
  dataproc_sa: "service-1023172132421@dataproc-accounts.iam.gserviceaccount.com",
  container_registry_sa: "service-1023172132421@containerregistry.iam.gserviceaccount.com",
  redis_sa: "service-1023172132421@cloud-redis.iam.gserviceaccount.com",
  serverless_robot_sa: "service-1023172132421@serverless-robot-prod.iam.gserviceaccount.com",
  service_networking_sa: "service-1023172132421@service-networking.iam.gserviceaccount.com",
  source_repo_sa: "service-1023172132421@sourcerepo-service-accounts.iam.gserviceaccount.com"

import_config "dev.secret.exs"
