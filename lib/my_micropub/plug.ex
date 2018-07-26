defmodule MyMicropub.Plug do
  use Plug.Router

  if Mix.env == :dev do
    use Plug.Debugger
  end

  use Plug.ErrorHandler

  plug :match

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug :dispatch

  forward "/micropub",
    to: PlugMicropub,
    init_opts: [
      handler: MyMicropub.Handler,
      json_encoder: Jason
    ]

  get "/media/:guid" do
    {file, content_type} = MyMicropub.Handler.get_media(guid)
    conn
    |> put_resp_content_type(content_type, nil)
    |> send_file(200, file)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

end
