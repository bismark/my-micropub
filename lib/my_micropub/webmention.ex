defmodule MyMicropub.Webmention do
  require Logger

  alias __MODULE__, as: This
  alias MyMicropub.Utils

  @regex ~r<(?:(?:https?):\/\/|www\.)(?:\([-A-Z0-9+&@#\/%=~_|$?!:,.]*\)|[-A-Z0-9+&@#\/%=~_|$?!:,.])*(?:\([-A-Z0-9+&@#\/%=~_|$?!:,.]*\)|[A-Z0-9+&@#\/%=~_|$])>i

  def handle(conn) do
    with :ok <- check_content_type(conn),
         {:ok, source, target} <- parse_body(conn),
         :ok <- check_target(target) do
      MyMicropub.Webmention.Validator.validate(source, target)
      :ok
    end
  end

  def send(metadata, content) do
    Task.Supervisor.start_child(This.TaskSupervisor, fn ->
      # TODO Change this...
      Process.sleep(2000)
      urls = collect_urls(metadata, content)

      source_url =
        hostname()
        |> struct(path: Path.join(["/post", metadata.slug]))
        |> URI.to_string()

      Enum.each(urls, fn url ->
        Task.Supervisor.start_child(This.TaskSupervisor, fn ->
          _send(url, source_url)
        end)
      end)
    end)
  end

  defp collect_urls(metadata, content) do
    urls = MapSet.new()

    urls =
      case metadata do
        %{type: "link", url: url} -> MapSet.put(urls, url)
        _ -> urls
      end

    case Regex.scan(@regex, content, capture: :all) do
      [] -> urls
      parsed -> Enum.reduce(parsed, urls, &MapSet.put(&2, List.first(&1)))
    end
  end

  defp _send(url, source_url) do
    Logger.debug("Sending #{inspect(url)} for #{inspect(source_url)}")
    options = [:with_body, follow_redirect: true, max_redirect: 20, max_body: 1_000_000]

    case :hackney.get(url, [], "", options) do
      {:ok, 200, res_headers, body} ->
        endpoint = get_endpoint(url, res_headers, body)

        case :hackney.post(endpoint, [], {:form, [{"target", url}, {"source", source_url}]}, [
               :with_body
             ]) do
          {:ok, res, _, _} when res < 299 ->
            Logger.debug("success!")

          error ->
            Logger.debug("Failed to send webmention: #{inspect(error)}")
        end

      res ->
        Logger.debug("failed to get target url #{inspect(url)}, #{inspect(res)}")
    end
  end

  defp get_endpoint(target_url, headers, body) do
    res =
      with nil <- Utils.parse_link_headers(headers),
           do: parse_body_for_endpoint(body)

    case res do
      nil ->
        :error

      res ->
        case URI.parse(res) do
          %URI{host: nil} = uri ->
            target_uri = URI.parse(target_url)

            case {uri.path && Path.split(uri.path), Path.basename(target_uri.path)} do
              {nil, _} ->
                URI.to_string(target_uri)

              {["/" | _], _} ->
                URI.to_string(%URI{target_uri | path: uri.path, query: uri.query})

              {[base | rest], base} ->
                URI.to_string(%URI{
                  target_uri
                  | path: Path.join(target_uri.path, rest),
                    query: uri.query
                })
            end

          _ ->
            res
        end
    end
  end

  defp parse_body_for_endpoint(body) do
    body
    |> Floki.find("[rel~=webmention]")
    |> Floki.find("link, a")
    |> Floki.attribute("href")
    |> List.first()
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
