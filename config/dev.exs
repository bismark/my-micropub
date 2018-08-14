use Mix.Config

config :logger,
  level: :debug

config :my_micropub,
  blog_path: "/Users/ryanjohnson/Programming/personal/iambismark.net",
  hostname: URI.parse("https://40ddbcd6.ngrok.io"),
  micropub_url: URI.parse("https://41873474.ngrok.io"),
  media_upload_path: "/tmp/micropub/"
