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

  defp posts_path, do: Path.join([Application.get_env(:my_micropub, :blog_path), "/content/post"])
end
