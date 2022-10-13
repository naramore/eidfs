defmodule Via.AST.Params do
  @moduledoc false
  alias Via.AST
  alias Via.AST.{Ident, Join, Prop}
  alias Via.Attr

  defstruct [:key, :params]
  @type t(key) :: %__MODULE__{
    key: key,
    params: map()
  }
  @type t :: t(params_key())
  @type join_key_params :: t(join_key_params_key())

  @type params_key :: Prop.t() | Join.t() | Ident.t()
  @type join_key_params_key :: Prop.t() | Ident.t()

  @spec new(params_key() | Attr.t() | {module(), atom()}, map()) :: t()
  def new(key, params)
  def new(%{__struct__: s} = key, params) when s in [Prop, Ident, Join] do
    %__MODULE__{key: key, params: params}
  end
  def new(key, params) do
    %__MODULE__{key: Prop.new(key), params: params}
  end

  @spec parse(term(), Keyword.t()) :: {:ok, t()} | {:error, reason :: term()}
  def parse(data, opts \\ [])
  def parse(%__MODULE__{} = params, _opts), do: {:ok, params}
  def parse({key, params}, opts) when is_map(params) do
    case parse_key(key, opts) do
      {:ok, key} -> {:ok, %__MODULE__{key: key, params: params}}
      {:error, reason} -> {:error, reason}
    end
  end
  def parse(x, _opts), do: {:error, {:invalid_params_expr, x}}

  defp parse_key(key, opts) do
    opts
    |> Keyword.get(:parent)
    |> case do
      :join -> [&Prop.parse/1, &Ident.parse/1]
      _ -> [&Prop.parse/1, &Ident.parse/1, &Join.parse/1]
    end
    |> then(&AST.parse_expr(key, &1))
  end

  defimpl Via.Shapify do
    def to_shape(params), do: @protocol.to_shape(get_key(params))

    def get_key(%@for{key: key}), do: @protocol.get_key(key)
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%{key: key, params: params}, opts) do
      container_doc("Via.join(", [key, params], ")", opts, &@protocol.inspect/2, [break: :flex, separator: ","])
    end
  end
end
