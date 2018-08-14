defmodule MyMicropub.Webmention do
  require Logger

  alias MyMicropub.Utils

  def handle(conn) do
    with :ok <- check_content_type(conn),
         {:ok, source, target} <- parse_body(conn),
         :ok <- check_target(target) do
      MyMicropub.Webmention.Validator.validate(source, target)
      :ok
    end
  end

  defp check_content_type(conn) do
    with [type] <- Plug.Conn.get_req_header(conn, "content-type"),
         {:ok, "application", "x-www-form-urlencoded", _} <- Plug.Conn.Utils.content_type(type) do
      :ok
    else
      _ ->
        Logger.debug("bad content type")
        :error
    end
  end

  defp parse_body(%{body_params: %{"source" => source, "target" => target}}) do
    source = URI.parse(source)
    target = URI.parse(target)

    cond do
      URI.to_string(source) == URI.to_string(target) ->
        Logger.debug("source and target match")
        :error

      source.scheme not in ["http", "https"] ->
        Logger.debug("source not http(s)")
        :error

      target.scheme != "https" ->
        Logger.debug("target not http(s)")
        :error

      target.host != hostname().host ->
        Logger.debug("target different host")
        :error

      true ->
        {:ok, source, target}
    end
  end

  defp check_target(target) do
    with {:ok, slug} <- Utils.parse_slug(target.path),
         do: check_file(slug)
  end

  defp check_file(slug) do
    if File.exists?(Utils.post_path(slug)) do
      :ok
    else
      Logger.debug("target file doesn't exist")
      :error
    end
  end

  defp hostname, do: Application.get_env(:my_micropub, :hostname)
end
