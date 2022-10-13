defmodule Via.Attr do
  @moduledoc false

  defstruct [:namespace, :name]
  @type t :: %__MODULE__{
    namespace: atom(),
    name: atom()
  }

  @spec new(atom(), atom()) :: t
  def new(namespace, name) do
    %__MODULE__{
      namespace: namespace,
      name: name
    }
  end

  @spec attr(atom() | nil, atom()) :: Macro.t()
  defmacro attr(namespace \\ nil, name) do
    quote do
      if is_nil(unquote(namespace)) do
        Via.Attr.new(__MODULE__, unquote(name))
      else
        Via.Attr.new(unquote(namespace), unquote(name))
      end
    end
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(attr, opts) do
      container_doc("Via.attr(", [attr.namespace, attr.name], ")", opts, &@protocol.inspect/2, [break: :flex, separator: ","])
    end
  end
end
