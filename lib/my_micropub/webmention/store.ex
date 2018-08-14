defmodule MyMicropub.Webmention.Store do
  use Agent

  alias __MODULE__, as: This
  alias MyMicropub.Utils

  def start_link(_) do
    Agent.start_link(fn -> %{} end, name: This)
  end

  def add(source, target) do
    {:ok, slug} = Utils.parse_slug(target.path)

    Agent.update(This, fn state ->
      Map.update(state, slug, [source], &[source | &1])
    end)
  end

  def all() do
    Agent.get(This, & &1)
  end
end
