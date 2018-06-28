defmodule MyMicropub.Handler do
  @behaviour PlugMicropub.HandlerBehaviour

  @posts_path Application.get_env(:my_micropub, :posts_path)
  @original_image_path Application.get_env(:my_micropub, :original_image_path)
  @media_path Application.get_env(:my_micropub, :media_path)
  @hostname Application.get_env(:my_micropub, :hostname)
  @widths [360, 720, 1200]

  @impl true
  def handle_create("entry", properties, access_token) do
    with :ok <- check_auth(access_token) do
      IO.inspect(properties)
      now = DateTime.utc_now()

      year = Integer.to_string(now.year)
      month = now.month |> Integer.to_string() |> String.pad_leading(2, "0")
      slug = now |> DateTime.to_unix() |> Integer.to_string()

      file_dir = Path.join([@posts_path, year, month])
      File.mkdir_p!(file_dir)

      file_path = Path.join([file_dir, "#{slug}.md"])

      content = parse_content(properties["content"])

      metadata =
        %{
          slug: slug,
          date: DateTime.to_iso8601(now),
          archive: ["#{year}-#{month}"]
        }
        |> handle_photo(properties)
        |> handle_title(properties)
        |> handle_bookmark(properties)
        |> handle_tags(properties)
        |> Jason.encode!()
        |> Jason.Formatter.pretty_print()

      File.write!(file_path, [metadata, "\n\n", content])

      url = @hostname <> "/post/" <> slug
      {:ok, :created, url}
    end
  end

  def handle_create(_, _, _), do: {:error, :invalid_request}

  @impl true
  def handle_update(url, replace, add, delete, @access_token) do
    :ok
  end

  def handle_update(_, _, _), do: {:error, :insufficient_scope}

  @impl true
  def handle_delete(url, @access_token) do
    :ok
  end

  def handle_delete(_, _), do: {:error, :insufficient_scope}

  @impl true
  def handle_undelete(url, @access_token) do
    :ok
  end

  def handle_undelete(_, _), do: {:error, :insufficient_scope}

  @impl true
  def handle_config_query(@access_token) do
    :ok
  end

  def handle_config_query(_), do: {:error, :insufficient_scope}

  @impl true
  def handle_source_query(url, properties, @access_token) do
    :ok
  end

  def handle_source_query(_, _, _), do: {:error, :insufficient_scope}

  @impl true
  def handle_media(file, @access_token) do
    :ok
  end

  defp handle_tags(metadata, %{"category" => tags}), do: Map.put(metadata, :tags, tags)
  defp handle_tags(metadata, _), do: metadata

  defp handle_title(metadata, %{"name" => [""]}), do: metadata
  defp handle_title(metadata, %{"name" => [name]}), do: Map.put(metadata, :title, name)
  defp handle_title(metadata, _), do: metadata

  defp handle_bookmark(metadata, %{"bookmark-of" => [url]}) do
    metadata
    |> Map.put(:type, "link")
    |> Map.put(:link, url)
  end
  defp handle_bookmark(metadata, _), do: metadata


  defp handle_photo(metadata, %{"photo" => [%Plug.Upload{} = upload]}) do
    {res, 0} =
      System.cmd("exiftool", [
        "-FileTypeExtension",
        "-Orientation",
        "-ImageWidth",
        "-n",
        "-json",
        upload.path
      ])

    image_metadata =
      res
      |> Jason.decode!()
      |> Enum.at(0)

    extension = Map.fetch!(image_metadata, "FileTypeExtension")
    image_width = Map.fetch!(image_metadata, "ImageWidth")
    orientation = image_metadata["Orientation"] || 1

    dest_path = Path.join([@original_image_path, metadata.slug])
    File.mkdir_p!(dest_path)
    dest_path = Path.join([dest_path, "1.#{extension}"])
    File.copy!(upload.path, dest_path)

    if orientation != 1 do
      System.cmd("exiftool", ["-Orientation=1", "-n", upload.path])
    end

    sizes = if extension in ["JPG", "PNG"] do
      Enum.reduce_while(@widths, [], fn
        target_width, acc when image_width > target_width ->
          create_thumbnail(upload.path, metadata.slug, extension, target_width)
          {:cont, [target_width | acc]}

        _, acc ->
          create_thumbnail(upload.path, metadata.slug, extension, image_width)
          {:halt, [image_width | acc]}
      end)
    else
      [image_width]
    end

    metadata =
      metadata
      |> Map.put(:imagetype, extension)
      |> Map.put(:type, "photo")

    case Enum.reverse(sizes) do
      @width -> metadata
      sizes -> Map.put(metadata, :imagesizes, sizes)
    end
  end

  defp handle_photo(metadata, _), do: metadata

  defp create_thumbnail(path, slug, extension, target_width) do
    dest_path = Path.join([@media_path, slug])
    File.mkdir_p!(dest_path)
    dest_path = Path.join([dest_path, "1-#{target_width}.#{extension}"])
    File.copy!(path, dest_path)

    _create_thumbnail(extension, dest_path, target_width)
  end

  defp _create_thumbnail("JPG", path, target_width) do
    System.cmd("mogrify", [
      "-filter",
      "Triangle",
      "-define",
      "filter:support=2",
      "-thumbnail",
      "#{target_width}",
      "-unsharp",
      "0.25x0.08+8.3+0.045",
      "-dither",
      "None",
      "-posterize",
      "136",
      "-quality",
      "82",
      "-define",
      "jpeg:fancy-upsampling=off",
      "-interlace",
      "none",
      "-colorspace",
      "sRGB",
      path
    ])

    System.cmd("jpeg-recompress", ["-m", "smallfry", "-s", "-Q", path, path])
  end

  defp _create_thumbnail("PNG", path, target_width) do
    System.cmd("mogrify", [
      "-filter",
      "Triangle",
      "-define",
      "filter:support=2",
      "-thumbnail",
      "#{target_width}",
      "-unsharp",
      "0.25x0.08+8.3+0.045",
      "-dither",
      "None",
      "-posterize",
      "136",
      "-quality",
      "82",
      "-define",
      "png:compression-filter=5",
      "-define",
      "png:compression-level=9",
      "-define",
      "png:compression-strategy=1",
      "-define",
      "png:exclude-chunk=all",
      "-interlace",
      "none",
      "-colorspace",
      "sRGB",
      path
    ])

    System.cmd("zopflipng", [path, path])
  end

  defp parse_content([%{"html" => html}]), do: html
  defp parse_content(content), do: content

  defp check_auth(access_token) do
    url = "https://tokens.indieauth.com/token"
    headers = [authorization: "Bearer #{access_token}", accept: "application/json; charset=utf-8"]

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200}} -> :ok
      _ -> {:error, :insufficient_scope}
    end
  end

end
