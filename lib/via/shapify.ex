defprotocol Via.Shapify do
  @moduledoc false

  @spec to_shape(t()) :: Via.shape()
  def to_shape(ast)

  @spec get_key(t()) :: Via.attr() | [Via.attr()]
  def get_key(ast)
end

defimpl Via.Shapify, for: List do
  def to_shape(list) do
    Enum.reduce(list, %{}, &Map.merge(&2, @protocol.to_shape(&1)))
  end

  def get_key(list), do: Enum.map(list, &@protocol.get_key/1)
end
