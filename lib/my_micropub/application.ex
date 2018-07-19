defmodule MyMicropub.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    case Code.ensure_loaded(ExSync) do
      {:module, ExSync = mod} -> mod.start()
      {:error, :nofile} -> :ok
    end

    children = [
      Plug.Adapters.Cowboy2.child_spec(
        scheme: :http,
        plug: MyMicropub.Plug,
        options: [port: 4001]
      )
    ]

    opts = [strategy: :one_for_one, name: MyMicropub.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
