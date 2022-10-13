defmodule Via.AST.Prop do
  @moduledoc false
  alias Via.Attr

  defstruct [:key]
  @type t :: %__MODULE__{
    key: Via.attr()
  }

  @spec new(Via.attr() | {module(), atom()}) :: t()
  def new(attr)
  def new(%Attr{} = attr) do
    %__MODULE__{key: attr}
  end
  def new({ns, n}) when is_atom(ns) and is_atom(n) do
    new(Attr.new(ns, n))
  end

  @spec parse(term()) :: {:ok, t()} | {:error, reason :: term()}
  def parse(data)
  def parse(%__MODULE__{} = prop), do: {:ok, prop}
  def parse(%Attr{} = attr), do: {:ok, %__MODULE__{key: attr}}
  def parse({ns, n}) when is_atom(ns) and is_atom(n), do: parse(Attr.new(ns, n))
  def parse(n) when is_atom(n), do: parse(Attr.new(nil, n))
  def parse(x), do: {:error, {:invalid_prop_expr, x}}

  defimpl Via.Shapify do
    alias Via.Attr

    def to_shape(prop), do: %{get_key(prop) => %{}}

    def get_key(%@for{key: %Attr{namespace: nil, name: key}}), do: key
    def get_key(%@for{key: key}), do: key
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%{key: attr}, opts) do
      container_doc("Via.prop({", [attr.namespace, attr.name], "})", opts, &@protocol.inspect/2, [break: :flex, separator: ","])
    end
  end
end
