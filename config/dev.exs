use Mix.Config

config :my_micropub,
  blog_path: "/Users/ryanjohnson/Programming/personal/iambismark.net",
  hostname: URI.parse("https://517e9c42.ngrok.io"),
  micropub_url: URI.parse("https://28b6c3b5.ngrok.io"),
  media_upload_path: "/tmp/micropub/"
