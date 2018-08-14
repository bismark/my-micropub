defmodule MyMicropub.Webmention.Validator do
  use GenServer

  require Logger

  alias __MODULE__, as: This
  alias MyMicropub.Webmention.Store

  def validate(source, target) do
    GenServer.cast(This, {:validate, source, target})
  end

  def start_link(_) do
    GenServer.start_link(This, [], name: This)
  end

  @impl true
  def init(_) do
    {:ok, nil}
  end

  @impl true
  def handle_cast({:validate, source, target}, _) do
    Logger.info("Validation #{URI.to_string(source)} for #{URI.to_string(target)}")
    headers = [{"accept", ["text/html, text/plain, application/json"]}]
    options = [:with_body, follow_redirect: true, max_redirect: 20, max_body: 1_000_000]

    valid? =
      case :hackney.get(URI.to_string(source), headers, "", options) do
        {:ok, 200, res_headers, body} ->
          handle_source(res_headers, body, URI.to_string(target))

        res ->
          Logger.debug("failed to get source: #{inspect(res)}")
          false
      end

    if valid? do
      Store.add(source, target)
    end

    {:noreply, nil}
  end

  defp handle_source(res_headers, body, target) do
    with type when type != :error <- parse_content_type(res_headers),
         do: parse_body(type, body, target)
  end

  defp parse_content_type(res_headers) do
    with {_, value} <- Enum.find(res_headers, &(String.downcase(elem(&1, 0)) == "content-type")),
         {:ok, base, type, _} <- Plug.Conn.Utils.content_type(value) do
      case {base, type} do
        {"text", "plain"} ->
          :plan

        {"text", "html"} ->
          :html

        {"application", "json"} ->
          :json

        other ->
          Logger.debug("Unsupported content type: #{inspect(other)}")
          :error
      end
    else
      error ->
        Logger.debug("Failure parsing content type: #{inspect(error)}")
        :error
    end
  end

  defp parse_body(:html, body, target) do
    body
    |> Floki.find("a")
    |> Floki.attribute("href")
    |> Enum.any?(&(&1 == target))
  end

  defp parse_body(:json, _body, _target) do
    Logger.warn("can't handle json...")
    :ok
  end

  defp parse_body(:plain, _body, _target) do
    Logger.warn("can't handle plain...")
    :ok
  end
end
