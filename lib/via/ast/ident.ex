defmodule Via.AST.Ident do
  @moduledoc false
  alias Via.AST.Prop
  alias Via.Attr

  defstruct [:prop, :id]
  @type t :: %__MODULE__{
    prop: Prop.t(),
    id: id()
  }

  @type id :: term()

  @spec new(Prop.t() | Attr.t() | {module(), atom()}, term()) :: t()
  def new(prop, id)
  def new(%Prop{} = prop, id) do
    %__MODULE__{prop: prop, id: id}
  end
  def new(attr, id) do
    new(Prop.new(attr), id)
  end

  @spec parse(term()) :: {:ok, t()} | {:error, reason :: term()}
  def parse(data)
  def parse(%__MODULE__{} = ident), do: {:ok, ident}
  def parse([prop, id]) do
    case Prop.parse(prop) do
      {:ok, prop} -> {:ok, %__MODULE__{prop: prop, id: id}}
      {:error, reason} -> {:error, reason}
    end
  end
  def parse(x), do: {:error, {:invalid_ident_expr, x}}

  defimpl Via.Shapify do
    def to_shape(ident), do: %{get_key(ident) => %{}}

    def get_key(%@for{prop: prop}), do: @protocol.get_key(prop)
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%{prop: prop, id: id}, opts) do
      container_doc("Via.ident(", [prop, id], ")", opts, &@protocol.inspect/2, [break: :flex, separator: ","])
    end
  end
end
