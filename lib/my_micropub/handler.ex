defmodule MyMicropub.Handler do
  @behaviour PlugMicropub.HandlerBehaviour

  @widths [360, 720, 1200]

  @json_opts [pretty: [indent: "    "]]

  @supported_properties %{
    "name" => "title",
    "category" => "tags",
    "published" => "date",
    "content" => "content",
    "uid" => "slug"
  }

  @list_properties ["tags", "archive"]

  @impl true
  def handle_create("entry", properties, access_token) do
    with :ok <- check_auth(access_token) do
      # IO.inspect(properties)
      now = DateTime.utc_now()

      year = Integer.to_string(now.year)
      month = now.month |> Integer.to_string() |> String.pad_leading(2, "0")
      slug = now |> DateTime.to_unix() |> Integer.to_string()

      file_dir = Path.join([posts_path(), year, month])
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
        |> Jason.encode!(@json_opts)

      File.write!(file_path, [metadata, "\n\n", content])

      url = hostname() <> "/post/" <> slug
      {:ok, :created, url}
    end
  end

  def handle_create(_, _, _), do: {:error, :invalid_request}

  @impl true
  def handle_update(url, replace, add, delete, access_token) do
    with :ok <- check_auth(access_token) do
      # IO.inspect replace
      # IO.inspect add
      # IO.inspect delete
      slug = parse_url(url)
      file_path = file_path(slug)
      post = read_post(file_path)

      post =
        replace
        |> Enum.filter(&Map.has_key?(@supported_properties, elem(&1, 0)))
        |> Enum.reduce(post, fn {k, v}, post ->
          tag = Map.fetch!(@supported_properties, k)
          Map.put(post, tag, v)
        end)

      post =
        add
        |> Enum.filter(&Map.has_key?(@supported_properties, elem(&1, 0)))
        |> Enum.reduce(post, fn {k, v}, post ->
          tag = Map.fetch!(@supported_properties, k)
          Map.update(post, tag, v, &(&1 ++ v))
        end)

      post =
        delete
        |> Enum.filter(fn
          {k, _} -> Map.has_key?(@supported_properties, k)
          k -> Map.has_key?(@supported_properties, k)
        end)
        |> Enum.reduce(post, fn
          {k, v}, post ->
            tag = Map.fetch!(@supported_properties, k)
            Map.update(post, tag, [], &(&1 -- v))

          k, post ->
            tag = Map.fetch!(@supported_properties, k)
            Map.delete(post, tag)
        end)

      post =
        Map.new(post, fn
          {k, v} when k in @list_properties ->
            {k, v}

          {k, [v]} ->
            v =
              v
              |> String.split(~r/\R/)
              |> Enum.join("\n")

            {k, v}
        end)

      # IO.inspect post

      {content, metadata} = Map.pop(post, "content")

      date =
        metadata
        |> Map.fetch!("date")
        |> NaiveDateTime.from_iso8601!()
        |> DateTime.from_naive!("Etc/UTC")

      new_slug = date |> DateTime.to_unix()

      if new_slug == slug do
        metadata = Jason.encode!(metadata, @json_opts)
        File.write!(file_path, [metadata, "\n\n", content])
        :ok
      else
        year = Integer.to_string(date.year)
        month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
        file_dir = Path.join([posts_path(), year, month])
        File.mkdir_p!(file_dir)
        new_file_path = Path.join([file_dir, "#{new_slug}.md"])

        metadata =
          metadata
          |> Map.put("slug", Integer.to_string(new_slug))
          |> Map.put("archive", ["#{year}-#{month}"])
          |> Jason.encode!(@json_opts)

        # IO.inspect(new_file_path)
        # IO.inspect(file_path)
        File.write!(new_file_path, [metadata, "\n\n", content])
        File.rm!(file_path)
        url = hostname() <> "/post/" <> Integer.to_string(new_slug)
        {:ok, url}
      end
    end
  end

  def handle_update(_, _, _), do: {:error, :insufficient_scope}

  @impl true
  def handle_delete(url, access_token) do
    :ok
  end

  def handle_delete(_, _), do: {:error, :insufficient_scope}

  @impl true
  def handle_undelete(url, access_token) do
    :ok
  end

  def handle_undelete(_, _), do: {:error, :insufficient_scope}

  @impl true
  def handle_config_query(access_token) do
    with :ok <- check_auth(access_token) do
      {:ok, %{}}
    end
  end

  @impl true
  def handle_source_query(url, properties, access_token) do
    with :ok <- check_auth(access_token) do
      slug = parse_url(url)
      file_path = file_path(slug)
      post = read_post(file_path)

      res =
        case properties do
          [] ->
            # Just return what we know about if its there
            Enum.reduce(@supported_properties, %{}, fn {ex_prop, in_prop}, acc ->
              case Map.fetch(post, in_prop) do
                :error -> acc
                {:ok, value} -> Map.put(acc, ex_prop, value)
              end
            end)

          list ->
            # Return everything they asked for, defaulting to empty list if we
            # don't know about it or don't have it
            Enum.reduce(list, %{}, fn property, acc ->
              case Map.fetch(@supported_properties, property) do
                :error ->
                  Map.put(acc, property, [])

                {:ok, tag} ->
                  case Map.fetch(post, tag) do
                    :error -> Map.put(acc, property, [])
                    {:ok, value} -> Map.put(acc, property, value)
                  end
              end
            end)
        end

      {:ok, %{"properties" => res}}
    end
  end

  @impl true
  def handle_media(file, access_token) do
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

    dest_path = Path.join([original_image_path(), metadata.slug])
    File.mkdir_p!(dest_path)
    dest_path = Path.join([dest_path, "1.#{extension}"])
    File.copy!(upload.path, dest_path)

    if orientation != 1 do
      System.cmd("exiftool", ["-Orientation=1", "-n", upload.path])
    end

    sizes =
      if extension in ["JPG", "PNG"] do
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
      @widths -> metadata
      sizes -> Map.put(metadata, :imagesizes, sizes)
    end
  end

  defp handle_photo(metadata, _), do: metadata

  defp create_thumbnail(path, slug, extension, target_width) do
    dest_path = Path.join([media_path(), slug])
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

  defp parse_url(url) do
    uri = URI.parse(url)

    uri.path
    |> Path.basename()
    |> String.to_integer()
  end

  def read_post(path) do
    {metadata, content} =
      path
      |> File.stream!()
      |> Enum.reduce({true, ""}, fn
        "\n", {true, acc} = res ->
          if String.ends_with?(acc, "}\n") do
            {Jason.decode!(acc), ""}
          else
            res
          end

        line, {true, acc} ->
          {true, acc <> line}

        line, {metadata, acc} ->
          {metadata, acc <> line}
      end)

    metadata
    |> Map.new(fn
      {k, list} when is_list(list) -> {k, list}
      {k, other} -> {k, [other]}
    end)
    |> Map.put("content", [content])
  end

  defp file_path(slug) do
    date = DateTime.from_unix!(slug)
    year = Integer.to_string(date.year)
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    Path.join([posts_path(), year, month, "#{slug}.md"])
  end

  defp posts_path, do: Application.get_env(:my_micropub, :posts_path)
  defp original_image_path, do: Application.get_env(:my_micropub, :original_image_path)
  defp media_path, do: Application.get_env(:my_micropub, :media_path)
  defp hostname, do: Application.get_env(:my_micropub, :hostname)
end
