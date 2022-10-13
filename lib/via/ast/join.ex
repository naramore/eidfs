defmodule Via.AST.Join do
  @moduledoc false
  alias Via.AST
  alias Via.AST.{Ident, Params, Prop}

  defstruct [:key, :query]
  @type t :: %__MODULE__{
    key: key(),
    query: [AST.query_expr(), ...] | AST.recursion()
  }

  @type key() :: Ident.t() | Prop.t() | Params.join_key_params()

  @spec new(key() | Attr.t() | {module(), atom()}, [AST.query_expr(), ...] | AST.recursion()) :: t()
  def new(key, query)
  def new(%{__struct__: s} = key, query) when s in [Prop, Ident, Params] do
    %__MODULE__{key: key, query: query}
  end
  def new(key, query) do
    %__MODULE__{key: Prop.new(key), query: query}
  end

  @spec parse(term()) :: {:ok, t()} | {:error, reason :: term()}
  def parse(%__MODULE__{} = join), do: {:ok, join}
  def parse(%{} = x) when map_size(x) == 1 do
    with [{k, v}] = Enum.into(x, []),
         {:ok, key} <- AST.parse_expr(k, [&Prop.parse/1, &Ident.parse/1, &Params.parse(&1, parent: :join)]),
         {:ok, query} <- parse_query(v) do
      {:ok, %__MODULE__{key: key, query: query}}
    else
      {:error, reason} -> {:error, reason}
      x -> {:error, {:unknown, x}}
    end
  end
  def parse(x), do: {:error, {:invalid_join_expr, x}}

  defp parse_query(:...), do: :...
  defp parse_query(x) when is_integer(x) and x > 0, do: x
  defp parse_query(query) do
    query
    |> Enum.reduce_while({:ok, []}, fn x, {:ok, acc} ->
      case AST.parse_expr(x, [&Prop.parse/1, &Ident.parse/1, &Params.parse/1, &parse/1]) do
        {:ok, x} -> {:cont, {:ok, [x | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, query} -> {:ok, :lists.reverse(query)}
      {:error, reason} -> {:error, reason}
    end
  end

  defimpl Via.Shapify do
    def to_shape(%@for{query: query} = join) when is_integer(query) and query > 0 do
      %{get_key(join) => %{}}
    end
    def to_shape(%@for{query: :...} = join) do
      %{get_key(join) => %{}}
    end
    def to_shape(%@for{query: query} = join) do
      %{get_key(join) => @protocol.to_shape(query)}
    end

    def get_key(%@for{key: key}), do: @protocol.get_key(key)
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%{key: key, query: query}, opts) do
      container_doc("Via.join(", [key, query], ")", opts, &@protocol.inspect/2, [break: :flex, separator: ","])
    end
  end
end
