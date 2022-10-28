import Config

config :faktory_user, FaktoryWorker,
  connection: [
    host: "localhost",
    port: 7419,
    password: nil,
    use_tls: false
  ],
  pool: [
    size: 15
  ],
  worker_pool: [
    size: 16,
    queues: [
      {"default", max_concurrency: 10}
    ]
  ]
