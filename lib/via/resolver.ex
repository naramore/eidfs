defmodule Via.ResolverOld do
  @moduledoc false

  # defresolver
  # resolver
  # alias-resolver(from, to)
  # equivalence-resolver(a, b)
  # constantly-resolver(attr, val)
  # constantly-fun-resolver(attr, (env -> val))
  # single-attr-resolver(source, target, (val -> val))
  # single-attr-with-env-resolver(source, target, (val, env -> val))
  # static-table-resolver(attr, table)
  # static-attribute-map-resolver
  # attribute-table-resolver
  # env-table-resolver
  # edn-file-resolver
  # global-data-resolver

  # TODO: params, transform, cache, batch
  defstruct id: nil,
            resolve: nil,
            input: [],
            output: [],
            config: %{}
  @type t :: %__MODULE__{
    id: id(),
    resolve: resolve_fun(),
    input: [Via.attr()],
    output: [Via.attr()],
    config: map()
  }

  @type resolve_fun :: (env :: map(), input :: map() -> output :: map())
  @type id :: term
  @type index_oir :: %{
    optional(Via.attr()) => %{
      optional(%{optional(Via.attr()) => Via.shape()}) => MapSet.t(id())
    }
  }
  @type index_io :: %{
    optional(MapSet.t(Via.attr())) => %{
      optional(Via.attr()) => Via.shape()
    }
  }
  @type attrs :: Via.attr() | MapSet.t(Via.attr())
  @type index_attributes :: %{
    optional(attrs()) => %{
      id: attrs(),
      input_in: MapSet.t(id()),
      output_in: MapSet.t(id()),
      provides: %{optional(attrs()) => MapSet.t(id())},
      reach_via: %{optional(attrs()) => MapSet.t(id())},
      combinations: MapSet.t(attrs())
    }
  }
  @type index_resolvers :: %{optional(id()) => t()}
  @type indexes :: %{
    index_oir: index_oir(),
    index_io: index_io(),
    index_attributes: index_attributes(),
    index_resolvers: index_resolvers()
  }
  @type registree :: t() | indexes() | [registree()]

  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id),
      resolve: Keyword.get(opts, :resolve),
      input: Keyword.get(opts, :input, []),
      output: Keyword.get(opts, :output, []),
      config: Keyword.get(opts, :config, %{})
    }
  end

  @spec build(Keyword.t()) :: {:ok, t()} | {:error, reason :: term()}
  def build(_opts \\ []) do
    {:error, :not_implemented}
  end

  # @spec build!(Keyword.t()) :: t() | no_return()
  # def build!(opts \\ []) do
  #   case build(opts) do
  #     {:ok, resolver} ->
  #       resolver

  #     {:error, reason} ->
  #       raise %ArgumentError{message: reason}
  #   end
  # end

  @spec merge_indexes(indexes(), indexes()) :: indexes()
  def merge_indexes(ia, ib) do
    Enum.reduce(ib, ia, fn
      {:index_resolvers, v}, acc ->
        Map.update(acc, :index_resolvers, v, &merge_resolvers!(&1, v))

      {:index_oir, v}, acc ->
        Map.update(acc, :index_oir, v, &merge_oir(&1, v))

      {k, v}, acc ->
        Map.update(acc, k, v, &merge_grow(&1, v))
    end)
  end

  @spec merge_resolvers!(index_resolvers(), index_resolvers()) :: index_resolvers() | no_return()
  defp merge_resolvers!(a, b) do
    Enum.reduce(b, a, fn {k, v}, acc ->
      if Map.has_key?(acc, k) do
        raise %ArgumentError{message: "Tried to register duplicated resolver: #{k}"}
      else
        Map.put(acc, k, v)
      end
    end)
  end

  @spec merge_oir(index_oir(), index_oir()) :: index_oir()
  defp merge_oir(a, b) do
    Map.merge(a, b, fn _, c, d ->
      Map.merge(c, d, fn _, e, f ->
        MapSet.union(e, f)
      end)
    end)
  end

  defp merge_grow(a, b)
  defp merge_grow(nil, nil), do: %{}
  defp merge_grow(%MapSet{} = a, %MapSet{} = b), do: MapSet.union(a, b)
  defp merge_grow(%{} = a, %{} = b), do: Map.merge(a, b, fn _, x, y -> merge_grow(x, y) end)
  defp merge_grow(a, nil), do: a
  defp merge_grow(_a, b), do: b

  @spec register(indexes(), registree()) :: indexes()
  def register(indexes, registree)
  def register(indexes, %__MODULE__{} = resolver) do
    register_resolver(resolver, indexes)
  end
  def register(indexes, %{} = more_indexes) do
    merge_indexes(indexes, more_indexes)
  end
  def register(indexes, operations) when is_list(operations) do
    Enum.reduce(operations, indexes, &register/2)
  end

  @spec register_resolver(t(), indexes()) :: indexes()
  defp register_resolver(resolver, indexes) do
    merge_indexes(indexes, %{
      index_resolvers: %{resolver.id => resolver},
      #index_attributes: get_resolver_attributes(resolver),
      index_io: get_index_io(resolver),
      index_oir: get_index_oir(resolver)
    })
  end

  # defp get_resolver_attributes(r) do
  #   r.input
  #   # inputs
  #   |> Enum.reduce(%{}, fn in_attr, idx ->
  #   end)
  #   # combinations
  #   |> then(&if Enum.count(r.input) > 1 do
  #     Enum.reduce(r.input, &1, fn in_attr, idx ->
  #     end)
  #   else
  #     &1
  #   end)
  #   # provides
  #   |> then(&Enum.reduce(r.output, &1, fn out_attr, idx ->
  #   end))
  #   # leaf / branches
  #   |> then(&Enum.reduce(r.output, &1, fn ->
  #   end))
  # end

  defp get_index_io(r) do
    case Via.expr_to_shape(r.output) do
      {:ok, shape} -> %{MapSet.new(r.input) => shape}
      _ -> %{}
    end
  end

  defp get_index_oir(r) do
    requires = Via.expr_to_shape(r.input)

    r.output
    |> Via.root_properties()
    |> Enum.reduce(%{}, fn x, acc ->
      if Enum.member?(requires, x) do
        acc
      else
        Map.update(acc, x, %{requires => MapSet.new([r.id])}, fn i ->
          Map.update(i, requires, MapSet.new([r.id]), fn rs ->
            MapSet.put(rs, r.id)
          end)
        end)
      end
    end)
  end

  @spec get_resolver(indexes(), id()) :: {:ok, t()} | {:error, :not_found}
  def get_resolver(indexes, resolver_id) do
    case get_in(indexes, [:index_resolvers, resolver_id]) do
      %__MODULE__{} = resolver -> {:ok, resolver}
      _ -> {:error, :not_found}
    end
  end
end
