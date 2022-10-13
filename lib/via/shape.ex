defmodule Via.Shape do
  @moduledoc false

  @type t(x) :: %{optional(x) => %{} | t(x)}
  @type t :: t(any())
  @type data :: map() | nil

  @spec from_ast(Via.ast()) :: t()
  def from_ast(ast) do
    Via.Shapify.to_shape(ast)
  end

  @spec merge(t(), t()) :: t()
  def merge(a, b)
  def merge(a, b) when is_map(a) and is_map(b) do
    Map.merge(a, b, fn _key, x, y -> merge(x, y) end)
  end
  def merge(a, _b) when is_map(a), do: a
  def merge(_a, b), do: b

  @spec difference(t() | nil, t() | nil) :: t()
  def difference(a, b)
  def difference(nil, _b), do: %{}
  def difference(a, nil), do: a
  def difference(a, b) do
    Enum.reduce(a, %{}, fn {k, v}, acc ->
      with {:ok, %{} = x} when map_size(x) > 0 <- Map.fetch(b, k),
           true <- is_map(v) and map_size(v) > 0,
           %{} = sd when map_size(sd) > 0 <- difference(v, x) do
        Map.put(acc, k, sd)
      else
        :error -> Map.put(acc, k, v)
        _ -> acc
      end
    end)
  end

  @spec intersection(t() | nil, t() | nil) :: t()
  def intersection(a, b)
  def intersection(nil, b), do: b
  def intersection(a, nil), do: a
  def intersection(a, b) do
    Enum.reduce(a, %{}, fn {k, v}, acc ->
      with {:ok, %{} = x} when map_size(x) > 0 <- Map.fetch(b, k),
           true <- is_map(v) and map_size(v) > 0,
           %{} = i when map_size(i) > 0 <- intersection(v, x) do
        Map.put(acc, k, i)
      else
        :error -> acc
        _ -> Map.put(acc, k, %{})
      end
    end)
  end

  # TODO: refactor
  @spec missing(t(), t()) :: t() | nil
  def missing(available_shape, required_shape) do
    required_shape
    |> Enum.map(fn {k, v} ->
      if Map.has_key?(available_shape, k) do
        if is_map(v) and map_size(v) > 0 do
          case missing(Map.get(available_shape, k), v) do
            %{} = x when map_size(x) > 0 ->
              {k, x}

            _ ->
              nil
          end
        end
      else
        {k, v}
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})
    |> then(&(if map_size(&1) > 0, do: &1))
  end

  # TODO: refactor
  @spec missing_from_data(data(), t()) :: t() | nil
  def missing_from_data(available_data, required_shape) do
    required_shape
    |> Enum.map(fn {k, v} ->
      sub_value = get(available_data, k)
      if contains?(available_data, k) do
        if is_map(v) and map_size(v) > 0 do
          if is_map(sub_value) do
            shape =
              sub_value
              |> Enum.map(&missing_from_data(&1, v))
              |> Enum.reduce(%{}, &merge(&2, &1))
            if map_size(shape) > 0 do
              {k, shape}
            end
          else
            sub_req = missing_from_data(sub_value, v)
            if is_map(sub_req) and map_size(sub_req) > 0 do
              {k, sub_req}
            end
          end
        else
          {k, v}
        end
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})
    |> then(&(if map_size(&1) > 0, do: &1))
  end

  # TODO: implement shape filtering
  @spec select(data(), t(), Keyword.t()) :: data()
  def select(data, shape, opts \\ [])
  def select(data, shape, opts) do
    Enum.reduce(shape, %{}, fn {k, v}, acc ->
      case Map.fetch(data, k) do
        :error -> acc
        {:ok, %{} = x} when map_size(x) > 0 ->
          Map.put(acc, k, select(x, v, opts))
        {:ok, x} when is_list(x) and length(x) > 0 ->
          Map.put(acc, k, Enum.map(x, &select(&1, v, opts)))
        {:ok, x} ->
          Map.put(acc, k, x)
      end
    end)
  end

  @spec get(term(), term(), term()) :: term()
  defp get(data, key, default \\ nil)
  defp get(data, key, default) when is_map(data),
    do: Map.get(data, key, default)
  defp get(_data, _key, default), do: default

  @spec contains?(term(), term()) :: boolean
  defp contains?(data, value)
  defp contains?(data, key) when is_map(data),
    do: Map.has_key?(data, key)
  defp contains?(_data, _value), do: false
end
