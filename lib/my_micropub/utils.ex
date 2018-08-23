defmodule MyMicropub.Utils do
  require Logger

  def post_dir(slug) do
    date = DateTime.from_unix!(slug)
    year = Integer.to_string(date.year)
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    Path.join([posts_path(), year, month, Integer.to_string(slug)])
  end

  def post_path(slug) do
    Path.join(post_dir(slug), "index.md")
  end

  def parse_slug(path) do
    case Path.split(path) do
      ["/", "post", slug] ->
        try do
          {:ok, String.to_integer(slug)}
        rescue
          ArgumentError ->
            Logger.debug("target invalid slug, #{inspect(slug)}")
            :error
        end

      _ ->
        Logger.debug("target invalid path, #{inspect(path)}")
        :error
    end
  end

  # Regexes lifted from https://github.com/simonrand/ex_link_header
  def parse_link_headers(headers) do
    headers
    |> Enum.filter(&(String.downcase(elem(&1, 0)) == "link"))
    |> Enum.map(fn {_, value} ->
      value
      |> String.split(~r{,\s*<}, trim: true)
      |> Enum.map(&Regex.run(~r{<?(.+)>; (.+)}, &1))
      |> Enum.reject(&match?(nil, &1))
      |> Enum.filter(fn [_, url, params] ->
        params
        |> String.split(";", trim: true)
        |> Enum.any?(fn param ->
          [_, name, value] = Regex.run(~r{(\w+)=\"?([\w\s]+)\"?}, param)

          case name do
            "rel" ->
              value
              |> String.split()
              |> Enum.member?("webmention")

            _ ->
              false
          end
        end)
      end)
      |> Enum.map(fn [_, url, _] -> url end)
      |> List.first()
    end)
    |> Enum.reject(&match?(nil, &1))
    |> List.first()
  end

  defp posts_path, do: Path.join([Application.get_env(:my_micropub, :blog_path), "/content/post"])
end
