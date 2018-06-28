defmodule MyMicropub.Plug do
  use Plug.Builder
  use Plug.ErrorHandler

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug PlugMicropub,
    handler: MyMicropub.Handler,
    json_encoder: Jason
end
