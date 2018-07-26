use Mix.Config

config :my_micropub,
  posts_path: "/Users/ryanjohnson/Programming/personal/iambismark.net/content/post",
  original_image_path: "/Users/ryanjohnson/Programming/personal/iambismark.net/original_images",
  media_path: "/Users/ryanjohnson/Programming/personal//iambismark.net/static/post",
  hostname: URI.parse("https://f313899c.ngrok.io"),
  micropub_url: URI.parse("https://18d36017.ngrok.io"),
  media_upload_path: "/tmp/micropub/"
