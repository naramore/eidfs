defmodule Via do
  @moduledoc false

  # env, register

  @type attr :: Via.Attr.t()
  @type ast :: Via.AST.query()
  @type shape :: Via.Shape.t(attr())
  @type expr :: Via.AST.expr()

  defdelegate attr(namespace, name), to: Via.Attr, as: :new
  defdelegate prop(attr), to: Via.AST.Prop, as: :new
  defdelegate ident(prop, id), to: Via.AST.Ident, as: :new
  defdelegate params(key, params), to: Via.AST.Params, as: :new
  defdelegate join(key, query), to: Via.AST.Join, as: :new

  # - [x] expr->ast
  # - [x] ast->expr
  # - [ ] {data,ast,expr}->shape
  # - [ ] shape->{ast,expr}
  # - [ ] data->expr = (data->shape + shape->expr)

  defdelegate expr_to_ast(expr), to: Via.AST, as: :from_expr
  defdelegate ast_to_expr(data), to: Via.AST, as: :to_expr
  defdelegate ast_to_shape(ast), to: Via.Shape, as: :from_ast

  @spec expr_to_shape(term()) :: {:ok, shape()} | {:error, reason :: term()}
  def expr_to_shape(expr) do
    case expr_to_ast(expr) do
      {:ok, ast} -> {:ok, ast_to_shape(ast)}
      {:error, reason} -> {:error, reason}
    end
  end

  def root_properties(expr) do
    expr
    |> expr_to_ast()
    |> Via.Shapify.get_key()
  end

  @spec attr!(atom() | nil, atom()) :: Macro.t()
  defmacro attr!(namespace \\ nil, name) do
    quote do
      if is_nil(unquote(namespace)) do
        Via.Attr.new(__MODULE__, unquote(name))
      else
        Via.Attr.new(unquote(namespace), unquote(name))
      end
    end
  end
end

# - [ ] resolver -> index graph
# - [x] resolver graph traversal based on ast
# - [ ] run graph attr construction
# - [ ] run graph ast construction
# - [ ] run graph execution
# - [ ] plugins / middleware / interceptors / hooks

# TODO: nested queries
# TODO: query *
# TODO: join recursion
# TODO: unions
# TODO: mutations
# TODO: subscription behaviour (e.g. implmented for Kernel.send/2, websockets, etc.)
# TODO: foreign environments / dynamic resolvers
# TODO: middleware / interceptor hooks
#         - :telemetry events
#         - batching
#         - results and execution caching
#         - placeholders?
#         - foreign / dynamic resolution
#         - snapshots
#         - type specs and docs
#         - dev linter
#         - resolver weight tracking
#         - complexity analysis
#         - filtering, sorting, and pagination

# TODO: RUN Node structure...
#       - what is needed at construction time?
#       - what is needed at run time?

# NOTE: the following need more investigation...
#         shape-reachable?
#         compute-nested-requirements
#           compute-run-graph on subquery (if exists)
#           get root resolvers
#           get their inputs
#           merge input shapes
#           merge ^ subquery shape
#           intersect ^ on resolver provides shape
#           => subset of resolver provides that directly / indirectly
#              provides requested subquery

defmodule Via.Resolver do
  @moduledoc false

  defstruct id: nil,
            input: %{},
            output: %{}
  @type t :: %__MODULE__{
    id: id(),
    input: Via.shape(),
    output: Via.shape()
  }

  @type id :: term()

  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @spec register(t(), :digraph.graph()) :: :ok
  def register(resolver, graph) do
    input = Enum.sort(Map.keys(resolver.input))

    # add all input and output attrs
    _ =
      input
      |> Enum.concat(Map.keys(resolver.output))
      |> Enum.each(&:digraph.add_vertex(graph, &1))

    # if resolver input size > 1 -> add that attr too
    if map_size(resolver.input) > 1 do
      :digraph.add_vertex(graph, input)
    end

    input =
      case input do
        [input] -> input
        otherwise -> otherwise
      end

    out_edges =
      graph
      |> :digraph.out_edges(input)
      |> Enum.map(&:digraph.edge(graph, &1))

    # generate all edges
    resolver.output
    |> Enum.map(fn {attr, shape} ->
      {input, attr, %{resolver.id => %{output: %{attr => shape}}}}
    end)
    |> Enum.each(fn {i, o, l} ->
      case Enum.find(out_edges, &match?({_, ^i, ^o, _}, &1)) do
        [{e, _, _, ll} | _] ->
          :digraph.add_edge(e, i, o, Map.merge(l, ll))

        _ ->
          :digraph.add_edge(graph, i, o, l)
      end
    end)

    :ok
  end
end

defmodule Via.Graph do
  @moduledoc false
  alias Via.AST.{Ident, Join, Params, Prop}
  alias Via.Resolver

  defstruct unreachable: MapSet.new([]),
            attr_trail: [],
            dg: nil,
            resolvers: %{}

  @type t :: %__MODULE__{
          unreachable: MapSet.t(attr()),
          attr_trail: [attr()],
          dg: :digraph.graph(),
          resolvers: %{optional(Resolver.id()) => Resolver.t()}
        }

  @type attr :: Via.attr() | [Via.attr()] | atom() | [atom()] | {atom(), atom()} | [{atom(), atom()}]
  @type edge :: {term(), attr(), attr(), map()}
  @type acc :: term()
  @type continuation :: :cont | {:halt, reason :: term()} | :done
  @type type :: {:pre | :post, :ast | :attr | :edge}

  @callback next_edges(attr(), t(), acc()) :: {[edge()], t(), acc}
  @callback visit(type(), continuation(), term(), t(), acc()) :: {continuation(), t(), acc()}
  # @callback pre_visit_attr(attr(), t(), acc()) :: {continuation(), t(), acc()}
  # @callback post_visit_attr(continuation(), attr(), t(), acc(), acc()) :: {continuation(), t(), acc()}
  # @callback pre_visit_edge(edge(), t(), acc()) :: {continuation(), t(), acc()}
  # @callback post_visit_edge(continuation(), edge(), t(), acc(), acc()) :: {continuation(), t(), acc()}
  # @callback pre_visit_ast(Via.ast(), t(), acc()) :: {continuation(), t(), acc()}
  # @callback post_visit_ast(continuation(), Via.ast(), t(), acc(), acc()) :: {continuation(), t(), acc()}

  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    if Keyword.has_key?(opts, :dg) do
      struct(__MODULE__, opts)
    else
      struct(__MODULE__, Keyword.put(opts, :dg, new_digraph()))
    end
  end

  @spec new_digraph() :: :digraph.graph()
  defp new_digraph do
    dg = :digraph.new()
    _ = :digraph.add_vertex(dg, [])
    dg
  end

  @spec register(t() | nil, Resolver.t() | [Resolver.t()]) :: {:ok, t()} | {:error, reason :: term()}
  def register(graph \\ nil, resolver_or_resolvers)
  def register(nil, resolver_or_resolvers) do
    register(new(), resolver_or_resolvers)
  end
  def register(graph, resolvers) when is_list(resolvers) do
    Enum.reduce_while(resolvers, {:ok, graph}, fn r, {:ok, g} ->
      case register(g, r) do
        {:ok, g} -> {:cont, {:ok, g}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
  def register(graph, resolver) do
    if Map.has_key?(graph.resolvers, resolver.id) do
      {:error, {:duplicate_resolver, resolver}}
    else
      _ = Resolver.register(resolver, graph.dg)
      {:ok, Map.update!(graph, :resolvers, &Map.put(&1, resolver.id, resolver))}
    end
  end

  @spec walk_ast(module, Via.ast() | Via.AST.t(), t(), acc()) :: {continuation(), t(), acc()}
  def walk_ast(module, ast, graph, acc)
  def walk_ast(module, query, graph, acc) when is_list(query) do
    walk_ast_impl(module, query, graph, acc, fn m, q, g, a ->
      Enum.reduce_while(q, {:cont, g, a}, fn ast, {_, g, a} ->
        case walk_ast(m, ast, g, a) do
          {{:halt, reason}, g, a} ->
            {:halt, {{:halt, reason}, g, a}}

          {c, g, a} ->
            {:cont, {c, g, a}}
        end
      end)
    end)
  end
  def walk_ast(module, %Prop{} = prop, graph, acc) do
    walk_ast_impl(module, prop, graph, acc, fn m, p, g, a ->
      walk_attr(m, p.key, g, a)
    end)
  end
  def walk_ast(module, %Ident{} = ident, graph, acc) do
    walk_ast_impl(module, ident, graph, acc, fn m, i, g, a ->
      walk_ast(m, i.key, g, a)
    end)
  end
  def walk_ast(module, %Params{} = params, graph, acc) do
    walk_ast_impl(module, params, graph, acc, fn m, p, g, a ->
      walk_ast(m, p.key, g, a)
    end)
  end
  def walk_ast(module, %Join{} = join, graph, acc) do
    walk_ast_impl(module, join, graph, acc, fn m, j, g, a ->
      # NOTE: walk the join subquery 1st???
      case walk_ast(m, j, g, a) do
        {{:halt, reason}, g, a} ->
          {{:halt, reason}, g, a}

        {c, g, a} ->
          Enum.reduce_while(j.query, {c, g, a}, fn ast, {_, g, a} ->
            case walk_ast(m, ast, g, a) do
              {{:halt, reason}, g, a} ->
                {:halt, {{:halt, reason}, g, a}}

              {c, g, a} ->
                {:cont, {c, g, a}}
            end
          end)
      end
    end)
  end

  @spec walk_ast_impl(module(), Via.ast() | Via.AST.t(), t(), acc(), (module(), Via.ast() | Via.AST.t(), t(), acc() -> {continuation(), t(), acc()})) :: {continuation(), t(), acc()}
  defp walk_ast_impl(module, ast, graph, acc, f) do
    case module.visit({:pre, :ast}, :cont, ast, graph, acc) do
      {:done, graph, acc} ->
        module.visit({:post, :ast}, :done, ast, graph, acc)

      {{:halt, reason}, graph, acc} ->
        module.visit({:post, :ast}, {:halt, reason}, ast, graph, acc)

      {:cont, graph, acc} ->
        {cont, graph, acc} = f.(module, ast, graph, acc)
        module.visit({:post, :ast}, cont, ast, graph, acc)
    end
  end

  @spec walk_attr(module, attr() | [attr()], t(), acc()) :: {continuation(), t(), acc()}
  def walk_attr(module, attr_or_attrs, graph, acc)
  def walk_attr(module, attrs, graph, acc) when is_list(attrs) do
    case module.visit({:pre, :attr}, :cont, attrs, graph, acc) do
      {:done, graph, new_acc} ->
        module.visit({:post, :attr}, :done, attrs, graph, new_acc)

      {{:halt, reason}, graph, new_acc} ->
        module.visit({:post, :attr}, {:halt, reason}, attrs, graph, new_acc)

      {:cont, graph, new_acc} ->
        {cont, graph, new_acc} =
          Enum.reduce_while(attrs, {:cont, graph, new_acc}, fn attr, {_, g, a} ->
            case walk_attr(module, attr, g, a) do
              {:done, g, a} ->
                {:cont, {:done, g, a}}
              {{:halt, r}, g, a} ->
                {:halt, {{:halt, r}, g, a}}
            end
          end)
        module.visit({:post, :attr}, cont, attrs, graph, new_acc)
    end
  end
  def walk_attr(module, attr, graph, acc) do
    case module.visit({:pre, :attr}, :cont, attr, graph, acc) do
      {:done, graph, new_acc} ->
        module.visit({:post, :attr}, :done, attr, graph, new_acc)

      {{:halt, reason}, graph, new_acc} when reason not in [:unreachable, :cyclic] ->
        module.visit({:post, :attr}, {:halt, reason}, attr, graph, new_acc)

      {cont, graph, new_acc} ->
        cond do
          unreachable?(graph, attr) or match?({:halt, :unreachable}, cont) ->
            # FIXME: updating unreachable should happen AFTER post_visit
            graph = Map.update!(graph, :unreachable, &MapSet.put(&1, attr))
            module.visit({:post, :attr}, {:halt, :unreachable}, attr, graph, new_acc)

          attr in Map.get(graph, :attr_trail, []) or match?({:halt, :cyclic}, cont) ->
            # FIXME: updating unreachable should happen AFTER post_visit
            graph = Map.update!(graph, :unreachable, &MapSet.put(&1, attr))
            module.visit({:post, :attr}, {:halt, :cyclic}, attr, graph, new_acc)

          true ->
            {next_edges, graph, new_acc} = module.next_edges(attr, graph, new_acc)
            {cont, graph, new_acc} =
              Enum.reduce(next_edges, {{:halt, :unreachable}, graph, new_acc}, fn edge, {c, g, a} ->
                case walk_edge(module, edge, g, a) do
                  {{:halt, _}, g, a} -> {c, g, a}
                  cga -> cga
                end
              end)
            # FIXME: updating unreachable should happen AFTER post_visit
            module.visit({:post, :attr}, cont, attr, graph, new_acc)
        end
    end
  end

  @spec unreachable?(t(), attr()) :: boolean()
  defp unreachable?(graph, attr) when is_list(attr) do
    attr in graph.unreachable or Enum.any?(attr, &(&1 in graph.unreachable))
  end
  defp unreachable?(graph, attr) do
    attr in graph.unreachable
  end

  @spec walk_edge(module, edge(), t(), acc()) :: {continuation(), t(), acc()}
  def walk_edge(module, {_, i, o, _} = edge, graph, acc) do
    with {:cont, g, a} <- module.visit({:pre, :edge}, :cont, edge, graph, acc),
         g = Map.update(g, :attr_trail, [o], &[o | &1]),
         {c, g, a} <- walk_attr(module, i, g, a) do
      module.visit({:post, :edge}, c, edge, Map.update!(g, :attr_trail, &tl/1), a)
    else
      {c, g, a} ->
        module.visit({:post, :edge}, c, edge, g, a)
    end
  end
end

defmodule Via.Plugin do
  @moduledoc false
  alias Via.Graph

  @type wrapped :: (Graph.type(), Graph.continuation(), term(), Graph.t(), Graph.acc() -> {Graph.continuation(), Graph.t(), Graph.acc()})

  @callback wrap(wrapped(), Graph.type(), Graph.continuation(), term(), Graph.t(), Graph.acc()) :: {Graph.continuation(), Graph.t(), Graph.acc()}

  @spec wrap_with_plugins([module()], wrapped()) :: wrapped()
  def wrap_with_plugins(plugins, f)
  def wrap_with_plugins([], f), do: f
  def wrap_with_plugins([p | ps], f) do
    wrap_with_plugins(ps, wrap_with_plugin(p, f))
  end

  @spec wrap_with_plugin(module(), wrapped()) :: wrapped()
  def wrap_with_plugin(plugin, f) do
    fn t, c, d, g, a ->
      plugin.wrap(f, t, c, d, g, a)
    end
  end
end

defmodule Via.Plugins do
  @moduledoc false
  alias Via.{Graph, Plugin}

  @behaviour Graph

  defstruct module: nil,
            plugins: [],
            acc: nil,
            state: %{}
  @type t :: %__MODULE__{
    module: module(),
    plugins: [module()],
    acc: Graph.acc(),
    state: map()
  }

  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @impl Graph
  def next_edges(attr, graph, acc) do
    {edges, graph, iacc} = acc.module.next_edges(attr, graph, acc.acc)
    {edges, graph, Map.put(acc, :acc, iacc)}
  end

  @impl Graph
  def visit({:post, t}, :cont, data, graph, acc) do
    visit({:post, t}, :done, data, graph, acc)
  end
  def visit(type, cont, data, graph, acc) do
    Plugin.wrap_with_plugins(
      acc.plugins,
      fn t, c, d, g, a ->
        {c, g, acc} = acc.module.visit(t, c, d, g, a.acc)
        {c, g, Map.put(a, :acc, acc)}
      end
    ).(type, cont, data, graph, acc)
  end
end

defmodule Via.Plan do
  @moduledoc false
  alias Digraph.{Edge, Vertex}
  alias Via.{Graph, Resolver}

  defstruct graph: Digraph.new(),
            resolver_index: %{},
            attr_index: %{},
            current: nil,
            branches: []
  @type t :: %__MODULE__{
    graph: Digraph.t(),
    resolver_index: %{optional(Resolver.id()) => MapSet.t(Vertex.id())},
    attr_index: %{optional(Graph.attr()) => MapSet.t(Vertex.id())},
    current: Vertex.id() | nil,
    branches: [Vertex.id()]
  }

  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @spec add_node(t(), map()) :: {Vertex.id(), t()}
  def add_node(plan, label) do
    Map.get_and_update!(plan, :graph, &Digraph.add_next_vertex(&1, label))
  end

  @spec add_resolver_node(t(), Resolver.t(), Via.AST.t()) :: {Vertex.id(), t()}
  def add_resolver_node(plan, resolver, _ast) do
    {vid, plan} = add_node(plan, %{
      type: :resolver,
      resolver: resolver.id,
      input: resolver.input,
      # FIXME: 1st -> intersect(Via.Shape.from_ast(ast), resolver.output)
      #        2nd -> walk_ast(...) -> get root resolvers -> get inputs -> merge w/ ast shape -> intersect w/ resolver.output
      expects: resolver.output
    })
    plan = Map.update!(plan, :resolver_index, fn ri -> Map.update(ri, resolver.id, MapSet.new([vid]), &MapSet.put(&1, vid)) end)
    plan = Enum.reduce(resolver.output, plan, fn {attr, _shape}, p ->
      Map.update!(p, :attr_index, fn ai -> Map.update(ai, attr, MapSet.new([vid]), &MapSet.put(&1, vid)) end)
    end)
    {vid, plan}
  end

  @spec add_or_node(t(), [Resolver.t()], Via.AST.t()) :: {Vertex.id(), [Vertex.id()], t()}
  def add_or_node(plan, resolvers, ast)
  def add_or_node(plan, [resolver], ast) do
    {v, p} = add_resolver_node(plan, resolver, ast)
    {v, [], p}
  end
  def add_or_node(plan, [_ | _] = resolvers, ast) do
    {vs, plan} =
      Enum.reduce(resolvers, {[], plan}, fn r, {vs, p} ->
        {v, p} = add_resolver_node(p, r, ast)
        {[v | vs], p}
      end)

    {ov, plan} =
      add_node(plan, %{
        type: :or,
        branches: vs
      })

    {:ok, {_, plan}} =
      vs
      |> Enum.map(&{ov, &1, %{type: :branch}})
      |> then(&add_edges(plan, &1))

    {ov, vs, plan}
  end

  @spec cascade_remove_node(t(), Vertex.id()) :: t()
  def cascade_remove_node(plan, node_id) do
    case Digraph.out_neighbours(plan.graph, node_id) do
      [] ->
        remove_node(plan, node_id)

      nodes ->
        nodes
        |> Enum.map(&Map.get(&1, :id))
        |> Enum.reduce(plan, &cascade_remove_node(&2, &1))
    end
  end

  @spec remove_node(t(), Vertex.id()) :: t()
  def remove_node(plan, node_id) do
    case Digraph.vertex(plan.graph, node_id) do
      %Vertex{label: %{expects: o, resolver: rid}} ->
        plan = Map.update!(plan, :resolver_index, fn ri -> Map.update(ri, rid, MapSet.new(), &MapSet.delete(&1, node_id)) end)
        plan = Enum.reduce(o, plan, fn {attr, _shape}, p ->
          Map.update!(p, :attr_index, fn ai -> Map.update(ai, attr, MapSet.new(), &MapSet.delete(&1, node_id)) end)
        end)
        Map.update!(plan, :graph, &Digraph.del_vertex(&1, node_id))

      _ ->
        Map.update!(plan, :graph, &Digraph.del_vertex(&1, node_id))
    end
  end

  @spec remove_nodes(t(), [Vertex.id()]) :: t()
  def remove_nodes(plan, node_ids) do
    Enum.reduce(node_ids, plan, &remove_node(&2, &1))
  end

  @spec add_edge(t(), Vertex.id(), Vertex.id(), Digraph.label()) :: {:ok, {Edge.t(), t()}} | {:error, reason :: term()}
  def add_edge(plan, v1, v2, label) do
    case Digraph.add_edge(plan.graph, v1, v2, label) do
      {:ok, {edge, graph}} -> {:ok,{edge, Map.put(plan, :graph, graph)}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec add_edges(t(), [{Vertex.id(), Vertex.id(), Digraph.label()}]) :: {:ok, {[Edge.t()], t()}} | {:error, reason :: term()}
  def add_edges(plan, edges) do
    Enum.reduce_while(edges, {:ok, {[], plan}}, fn {v1, v2, lb}, {:ok, {es, p}} ->
      case add_edge(p, v1, v2, lb) do
        {:ok, {e, p}} -> {:cont, {:ok, {[e | es], p}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec remove_edge(t(), Edge.id()) :: t()
  def remove_edge(plan, edge_id) do
    Map.update!(plan, :graph, &Digraph.del_edge(&1, edge_id))
  end

  @spec remove_edges(t(), [Edge.id()]) :: t()
  def remove_edges(plan, edge_ids) do
    Enum.reduce(edge_ids, plan, &remove_edge(&2, &1))
  end

  @spec inject_or_node(t(), Edge.id()) :: {:ok, {Vertex.id(), t()}} | {:error, reason :: term()}
  def inject_or_node(plan, edge_id) do
    with %Edge{v1: v1, v2: v2, label: l} <- Digraph.edge(plan.graph, edge_id),
         {ov, p} <- add_node(plan, %{type: :or, branches: [v1]}),
         {:ok, p} <- Enum.reduce_while(Digraph.in_edges(p.graph, v1), {:ok, p}, fn %Edge{id: eid, v1: vv1, label: l}, {:ok, p} ->
           case Digraph.add_edge(p.graph, eid, vv1, ov, l) do
             {:ok, {_, g}} -> {:cont, {:ok, %{p | graph: g}}}
             {:error, reason} -> {:halt, {:error, reason}}
           end
         end),
         {:ok, {_, p}} <- add_edge(p, ov, v1, %{type: :branch}),
         {:ok, {_, graph}} <- Digraph.add_edge(p.graph, edge_id, ov, v2, l) do
      {:ok, {ov, %{p | graph: graph}}}
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, {:edge_not_found, edge_id}}
    end
  end

  @spec add_branches(t(), Vertex.id(), [Vertex.id()]) :: {:ok, {Vertex.id(), t()}} | {:error, reason :: term()}
  def add_branches(plan, node_id, branch_ids) do
    case Digraph.vertex(plan.graph, node_id) do
      %Vertex{label: %{type: t} = l} when t in [:or, :and] ->
        plan
        |> Map.get_and_update!(:graph, fn g ->
          Digraph.add_vertex(g, node_id, Map.update!(l, :branches, &Enum.concat(&1, branch_ids)))
        end)
        |> then(&Enum.reduce_while(branch_ids, {:ok, &1}, fn bid, {:ok, {_, p}} ->
          case add_edge(p, node_id, bid, %{type: :branch}) do
            {:ok, {_, p}} -> {:cont, {:ok, {node_id, p}}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end))

      _ ->
        {:ok, {node_id, plan}}
    end
  end
end

defmodule Via.Planner do
  @moduledoc false
  alias Via.Graph
  require Logger

  @behaviour Graph

  defstruct available_data: %{},
            plan: Via.Plan.new(),
            resolver_trail: [],
            and_roots: [],
            audit: [],
            depth: 0
  @type t :: %__MODULE__{
    available_data: map(),
    plan: Via.Plan.t(),
    resolver_trail: [{Digraph.Vertex.id(), Graph.attr(), Graph.attr(), term()}],
    and_roots: [Digraph.Vertex.id()],
    audit: [term()],
    depth: non_neg_integer()
  }

  def snapshot(depth, msg) do
    depth = if depth >=0, do: depth, else: 0

    Stream.repeatedly(fn -> "-" end)
    |> Enum.take(depth)
    |> Enum.join("")
    |> then(&(if String.length(&1) > 0, do: "#{&1} ", else: &1))
    |> then(&"#{&1}#{msg}")
    |> IO.puts()
  end

  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @impl Graph
  def next_edges(attr, graph, planner) do
    graph.dg
    |> :digraph.in_edges(attr)
    |> Enum.map(&:digraph.edge(graph.dg, &1))
    |> then(&{&1, graph, planner})
  end

  @impl Graph
  def visit(type, cont, data, graph, planner)
  def visit({_, :ast}, cont, _ast, graph, planner) do
    {cont, graph, planner}
  end
  def visit({:pre, :attr}, _cont, attr, graph, planner) do
    planner = if is_list(attr) do
      Map.update!(planner, :depth, &(&1 + 1))
    else
      planner
    end

    if available?(planner, attr) do
      {:done, graph, planner}
    else
      {:cont, graph, planner}
    end
  end
  def visit({:post, :attr}, :done, attr, graph, planner) when is_list(attr) do
    {aid, planner} = Map.get_and_update!(planner, :plan, &Via.Plan.add_node(&1, %{type: :and, branches: planner.and_roots}))
    {:ok, {_, plan}} = Via.Plan.add_branches(planner.plan, aid, planner.and_roots)
    planner = Map.put(planner, :plan, plan)
    connect_to_next(planner, aid)

    planner = Map.update!(planner, :depth, &(&1 - 1))
    {:done, graph, Map.put(planner, :and_roots, [])}
  end
  def visit({:post, :attr}, cont, attr, graph, planner) when is_list(attr) do
    planner = Map.update!(planner, :depth, &(&1 - 1))
    cont = if match?({:halt, :cyclic}, cont), do: {:halt, :unreachable}, else: cont
    {cont, graph, Map.put(planner, :and_roots, [])}
  end
  def visit({:post, :attr}, cont, _attr, graph, planner) do
    cont = if match?({:halt, :cyclic}, cont), do: {:halt, :unreachable}, else: cont
    {cont, graph, planner}
  end
  def visit({:pre, :edge}, _cont, {_, i, o, rs}, graph, planner) do
    planner = Map.update!(planner, :depth, &(&1 + 1))
    {or_id, _vids, plan} = Via.Plan.add_or_node(
      planner.plan,
      Enum.map(rs, &Map.get(graph.resolvers, elem(&1, 0))),
      Via.AST.Prop.new({nil, nil})
    )

    planner
    |> Map.put(:plan, plan)
    |> Map.update!(:resolver_trail, &[{or_id, i, o, rs} | &1])
    |> then(&{:cont, graph, &1})
  end
  def visit({:post, :edge}, :done, _edge, graph, %{resolver_trail: [{id1, _, _, _} | _]} = planner) do
    planner
    |> Map.update!(:resolver_trail, &tl/1)
    |> connect_to_next(id1)
    |> Map.update!(:depth, &(&1 - 1))
    |> then(&{:done, graph, &1})
  end
  def visit({:post, :edge}, {:halt, reason}, _edge, graph, %{resolver_trail: [{v, _, _, _} | _]} = planner) do
    planner
    |> Map.update!(:plan, &Via.Plan.cascade_remove_node(&1, v))
    |> Map.update!(:resolver_trail, &tl/1)
    |> Map.update!(:depth, &(&1 - 1))
    |> then(&{{:halt, reason}, graph, &1})
  end

  # @impl Graph
  # def pre_visit_ast(_ast, graph, planner) do
  #   {:cont, graph, planner}
  # end

  # @impl Graph
  # def post_visit_ast(cont, _ast, graph, _old_planner, planner) do
  #   {cont, graph, planner}
  # end

  # @impl Graph
  # def pre_visit_attr(attr, graph, planner) do
  #   planner = if is_list(attr) do
  #     Map.update!(planner, :depth, &(&1 + 1))
  #   else
  #     planner
  #   end
  #   _ = snapshot(planner.depth, "pre_visit_attr(#{inspect(attr)}, _graph, _planner)")

  #   if available?(planner, attr) do
  #     {:done, graph, planner}
  #   else
  #     {:cont, graph, planner}
  #   end
  # end

  # @impl Graph
  # def post_visit_attr(:done, attr, graph, _old_planner, planner) when is_list(attr) do
  #   {aid, planner} = Map.get_and_update!(planner, :plan, &Via.Plan.add_node(&1, %{type: :and, branches: planner.and_roots}))
  #   {:ok, {_, plan}} = Via.Plan.add_branches(planner.plan, aid, planner.and_roots)
  #   planner = Map.put(planner, :plan, plan)
  #   connect_to_next(planner, aid)

  #   planner = Map.update!(planner, :depth, &(&1 - 1))
  #   {:done, graph, Map.put(planner, :and_roots, [])}
  # end
  # def post_visit_attr(cont, attr, graph, _old_planner, planner) when is_list(attr) do
  #   planner = Map.update!(planner, :depth, &(&1 - 1))
  #   cont = if match?({:halt, :cyclic}, cont), do: {:halt, :unreachable}, else: cont
  #   {cont, graph, Map.put(planner, :and_roots, [])}
  # end
  # def post_visit_attr(cont, _attr, graph, _old_planner, planner) do
  #   cont = if match?({:halt, :cyclic}, cont), do: {:halt, :unreachable}, else: cont
  #   {cont, graph, planner}
  # end

  # @impl Graph
  # def pre_visit_edge({_, i, o, rs}, graph, planner) do
  #   planner = Map.update!(planner, :depth, &(&1 + 1))
  #   {or_id, _vids, plan} = Via.Plan.add_or_node(
  #     planner.plan,
  #     Enum.map(rs, &Map.get(graph.resolvers, elem(&1, 0))),
  #     Via.AST.Prop.new({nil, nil})
  #   )

  #   planner
  #   |> Map.put(:plan, plan)
  #   |> Map.update!(:resolver_trail, &[{or_id, i, o, rs} | &1])
  #   |> then(&{:cont, graph, &1})
  # end

  @spec connect_to_next(t(), Digraph.Vertex.id()) :: t()
  defp connect_to_next(planner, id1) do
    case planner do
      %{resolver_trail: [{_, i2, _, _} | _]} = planner when is_list(i2) and length(i2) > 1 ->
        Map.update!(planner, :and_roots, &[id1 | &1])

      %{resolver_trail: [{id2, i2, o2, rs2} | _]} = planner when not is_list(i2) ->
        case Digraph.in_neighbours(planner.plan.graph, id2) do
          [] ->
            {:ok, {_, plan}} = Via.Plan.add_edge(planner.plan, id1, id2, [])
            Map.put(planner, :plan, plan)

          [%Digraph.Vertex{label: %{type: :resolver}}] ->
            [%Digraph.Edge{id: eid}] = Digraph.in_edges(planner.plan.graph, id2)
            {:ok, {oid, plan}} = Via.Plan.inject_or_node(planner.plan, eid)
            {:ok, {_, plan}} = Via.Plan.add_branches(plan, oid, [id1])
            Map.put(planner, :plan, plan)

          [%Digraph.Vertex{id: bid, label: %{type: t}}] when t in [:and, :or] ->
            {:ok, {_, plan}} = Via.Plan.add_branches(planner.plan, bid, [id1])
            Map.put(planner, :plan, plan)

          in_neighbours ->
            _ = Logger.warning(fn -> %{v1: %{id: id1}, v2: %{id: id2, i: i2, o: o2, rs: rs2}, v2_ins: in_neighbours} end)
            planner
        end

      planner ->
        planner
    end
  end

  # @impl Graph
  # def post_visit_edge(:done, _edge, graph, _old_planner, %{resolver_trail: [{id1, _, _, _} | _]} = planner) do
  #   planner
  #   |> Map.update!(:resolver_trail, &tl/1)
  #   |> connect_to_next(id1)
  #   |> Map.update!(:depth, &(&1 - 1))
  #   |> then(&{:done, graph, &1})
  # end
  # def post_visit_edge({:halt, reason}, _edge, graph, _old_planner, %{resolver_trail: [{v, _, _, _} | _]} = planner) do
  #   planner
  #   |> Map.update!(:plan, &Via.Plan.cascade_remove_node(&1, v))
  #   |> Map.update!(:resolver_trail, &tl/1)
  #   |> Map.update!(:depth, &(&1 - 1))
  #   |> then(&{{:halt, reason}, graph, &1})
  # end

  @spec available?(t(), Graph.attr()) :: boolean()
  defp available?(_planner, []), do: true
  defp available?(planner, attr) when is_list(attr) do
    Enum.all?(attr, &(&1 in Map.keys(planner.available_data)))
  end
  defp available?(planner, attr) do
    attr in Map.keys(planner.available_data)
  end

  # @spec add_to_audit(t(), atom(), term()) :: t()
  # defp add_to_audit(planner, key, val) do
  #   Map.update(planner, :audit, [{key, val}], &[{key, val} | &1])
  # end
end

defmodule Via.PlannerV2 do
  @moduledoc false
  alias Via.Graph

  @behaviour Graph

  @spec new() :: Via.Plugins.t()
  def new do
    Via.Plugins.new(
      module: Via.PlannerV2,
      plugins: [Via.PlannerV2.PrinterPlugin],
      acc: %{},
      state: %{depth: 0}
    )
  end

  @impl Graph
  def next_edges(attr, graph, planner) do
    graph.dg
    |> :digraph.in_edges(attr)
    |> Enum.map(&:digraph.edge(graph.dg, &1))
    |> then(&{&1, graph, planner})
  end

  @impl Graph
  def visit(_type, cont, _data, graph, planner) do
    {cont, graph, planner}
  end

  defmodule PrinterPlugin do
    @moduledoc false
    @behaviour Via.Plugin

    @impl Via.Plugin
    def wrap(f, t, c, d, g, a) do
      _ = print_stuff(:pre_depth_inc, t, c, d, g, a)
      a = if increase_depth?(t, c,d ), do: update_depth(a, &(&1 + 1), 1), else: a
      _ = print_stuff(:post_depth_inc, t, c, d, g, a)
      {cc, gg, aa} = f.(t, c, d, g, a)
      _ = print_stuff(:pre_depth_dec, t, cc, d, gg, aa)
      aa = if decrease_depth?(t, c, d), do: update_depth(aa, &(&1 - 1)), else: aa
      _ = print_stuff(:post_depth_dec, t, cc, d, gg, aa)
      {cc, gg, aa}
    end

    def increase_depth?(type, cont, data)
    def increase_depth?({:pre, :edge}, _, _), do: true
    def increase_depth?(_, _, _), do: false

    def decrease_depth?(type, cont, data)
    def decrease_depth?({:post, :edge}, _, _), do: true
    def decrease_depth?(_, _, _), do: false

    def print_stuff(where, type, cont, data, graph, acc)
    def print_stuff(:pre_depth_inc, {:pre, :attr}, _, attr, _, a) do
      if is_list(attr) do
        :ok
      else
        snapshot(a, "Process attribute #{inspect(attr)}")
      end
    end
    def print_stuff(:post_depth_inc, {:pre, :attr}, _, attr, _, _) do
      case attr do
        _ -> :ok
      end
    end
    def print_stuff(:pre_depth_dec, {:pre, :attr}, _, _, _, _) do
      :ok
    end
    def print_stuff(:post_depth_dec, {:pre, :attr}, _, _, _, _) do
      :ok
    end
    def print_stuff(:pre_depth_inc, {:post, :attr}, _, _, _, _) do
      :ok
    end
    def print_stuff(:post_depth_inc, {:post, :attr}, _, _, _, _) do
      :ok
    end
    def print_stuff(:pre_depth_dec, {:post, :attr}, cont, attr, _, a) do
      case cont do
        {:halt, :cycle} ->
          snapshot(a, "Attribute cycle detected for #{inspect(attr)}")
        _ ->
          :ok
      end
    end
    def print_stuff(:post_depth_dec, {:post, :attr}, _, _, _, _) do
      :ok
    end
    def print_stuff(:pre_depth_inc, {:pre, :edge}, _, {_, i, _, _}, _, a) do
      snapshot(a, "Add nodes for input path #{inspect(to_shape(i))}")
    end
    def print_stuff(:post_depth_inc, {:pre, :edge}, _, {_, i, o, _}, _, a) do
      _ = snapshot(a, "Computing #{inspect(o)} dependencies #{inspect(to_shape(i))}")
      snapshot(a, "Processing dependency #{inspect(to_shape(i))}")
    end
    def print_stuff(:pre_depth_dec, {:pre, :edge}, _, _, _, _) do
      :ok
    end
    def print_stuff(:post_depth_dec, {:pre, :edge}, _, _, _, _) do
      :ok
    end
    def print_stuff(:pre_depth_inc, {:post, :edge}, _, _, _, _) do
      :ok
    end
    def print_stuff(:post_depth_inc, {:post, :edge}, _, _, _, _) do
      :ok
    end
    def print_stuff(:pre_depth_dec, {:post, :edge}, cont, {_, i, _, _}, _, a) do
      case cont do
        {:halt, _} ->
          snapshot(a, "Mark path #{inspect(to_shape(i))} as unreachable")
        _ ->
          snapshot(a, "Complete computing deps #{inspect(to_shape(i))}")
      end
    end
    def print_stuff(:post_depth_dec, {:post, :edge}, _, {_, i, _, _}, _, a) do
      _ = snapshot(a, "Chained deps")
      case i do
        [_ | _] -> snapshot(a, "Create root AND")
        _ -> :ok
      end
    end
    def print_stuff(_where, _t, _c, _d, _g, _a) do
      :ok
    end

    defp to_shape(x) when is_list(x) do
      Enum.reduce(x, %{}, &Map.put(&2, &1, %{}))
    end
    defp to_shape(x) do
      %{x => %{}}
    end

    def update_depth(acc, f, default \\ 0) do
      Map.update!(acc, :state, fn s ->
        Map.update(s, :depth, default, f)
      end)
    end

    def snapshot(state_or_depth, message)
    def snapshot(%{state: state}, message) do
      snapshot(Map.get(state, :depth, 0), message)
    end
    def snapshot(depth, msg) when is_integer(depth) do
      depth = if depth < 0, do: 0, else: depth
      buffer = if depth == 0, do: "", else: " "

      Stream.repeatedly(fn -> "-" end)
      |> Enum.take(depth)
      |> then(&IO.puts("#{&1}#{buffer}#{msg}"))
    end
  end
end

defmodule Via.Example do
  def index_oir do
    ~S"""
    {
      :b {{:a {}} #{r1}},
      :c {{} #{s1}},
      :d {{:c {}} #{r2}},
      :e {{:c {}} #{r3}},
      :f {{:b {}, :d {}} #{r15}},
      :g {{:h {}} #{r11}},
      :h {{:i {}} #{r12}},
      :i {{:j {}} #{r13}},
      :j {{:g {}} #{r14}},
      :k {{:g {}} #{r10}
          {:f {}} #{r32}},
      :l {{:e {}} #{r4}},
      :m {{:l {}} #{r5}},
      :n {{:l {}} #{r6}},
      :o {{:n {}} #{r7}
          {:z {}} #{r23}},
      :p {{:m {}} #{r8},
          {:o {}} #{r9}
          {:k {}} #{r33}},
      :q {{} #{s2}},
      :r {{:q {}} #{r16}},
      :s {{:r {}, :w {}} #{r20}},
      :t {{} #{s3}},
      :u {{} #{s4}},
      :v {{:t {}} #{r17}
          {:u {}} #{r18}},
      :w {{:v {}} #{r19}},
      :y {{:s {}} #{r21}
          {:ac {}} #{r26}},
      :z {{:y {}} #{r22}
          {:ab {}} #{r25}},
      :ab {{:aa {}} #{r24}
           {:af {}} #{r30}
           {:ad {}} #{r31}},
      :ac {{:ad {}} #{r27}},
      :ad {{:ae {}} #{r28}},
      :ae {{} #{s5}},
      :af {{:ae {}} #{r29}}
    }
    """
  end

  def resolvers do
    [
      {[:a], [:b]},
      {[:c], [:d]},
      {[:c], [:e]},
      {[:e], [:l]},
      {[:l], [:m]},
      {[:l], [:n]},
      {[:n], [:o]},
      {[:m], [:p]},
      {[:o], [:p]},
      {[:g], [:k]},
      {[:h], [:g]},
      {[:i], [:h]},
      {[:j], [:i]},
      {[:g], [:j]},
      {[:d, :b], [:f]},
      {[:q], [:r]},
      {[:t], [:v]},
      {[:u], [:v]},
      {[:v], [:w]},
      {[:r, :w], [:s]},
      {[:s], [:y]},
      {[:y], [:z]},
      {[:z], [:o]},
      {[:aa], [:ab]},
      {[:ab], [:z]},
      {[:ac], [:y]},
      {[:ad], [:ac]},
      {[:ae], [:ad]},
      {[:ae], [:af]},
      {[:af], [:ab]},
      {[:ad], [:ab]},
      {[:f], [:k]},
      {[:k], [:p]},
    ]
    |> Enum.zip(1..33)
    |> Enum.map(fn {{i, o}, r} ->
      Via.Resolver.new(
        id: :"r#{r}",
        input: Enum.reduce(i, %{}, &Map.put(&2, &1, %{})),
        output: Enum.reduce(o, %{}, &Map.put(&2, &1, %{}))
      )
    end)
    |> Enum.concat(
      Enum.map(Enum.zip(1..5, [:c, :q, :t, :u, :ae]), fn {i, o} ->
        Via.Resolver.new(
          id: :"s#{i}",
          input: %{},
          output: %{o => %{}}
        )
      end)
    )
  end

  def graph do
    {:ok, graph} = Via.Graph.register(resolvers())
    graph
  end

  # {c, g, a} = Via.Example.test(); nil
  # Via.Example.read_plan(a.plan.graph)
  def test do
    Via.Graph.walk_attr(
      Via.Planner,
      :p,
      graph(),
      Via.Planner.new()
    )
  end

  # {c, g, a} = Via.Example.test2(); nil
  def test2 do
    Via.Graph.walk_attr(
      Via.Plugins,
      :p,
      graph(),
      Via.PlannerV2.new()
    )
  end

  def vplan(graph, node_or_id)
  def vplan(graph, %Digraph.Vertex{id: id, label: %{resolver: rid, input: i, expects: e}}) do
    resolver_node = {rid, Map.keys(i), Map.keys(e)}
    case Digraph.out_neighbours(graph, id) do
      [] -> [resolver_node]
      [next] -> [resolver_node | vplan(graph, next)]
    end
  end
  def vplan(graph, %Digraph.Vertex{id: id, label: %{type: t}}) when t in [:or, :and] do
    edges = Digraph.out_edges(graph, id)
    branches = Enum.filter(edges, &match?(%{label: %{type: :branch}}, &1))
    branch_node = {t, Enum.map(branches, &vplan(graph, &1.v2))}
    case Enum.reject(edges, &match?(%{label: %{type: :branch}}, &1)) do
      [] -> [branch_node]
      [next] -> [branch_node | vplan(graph, next)]
    end
  end
  def vplan(graph, node_id) do
    case Digraph.vertex(graph, node_id) do
      nil -> []
      vertex -> vplan(graph, vertex)
    end
  end

  def read_plan(graph) do
    graph
    |> Digraph.edges()
    |> Enum.map(&Map.get(&1, :v2))
    |> Enum.map(&{&1, Digraph.in_edges(graph, &1)})
    |> Enum.filter(&match?({_, []}, &1))
    |> Enum.map(&elem(&1, 0))
    |> Enum.map(&read_plan(graph, &1))
    |> Enum.concat()
  end

  def read_plan(graph, vertex, acc \\ [], path \\ [])
  def read_plan(graph, %Digraph.Vertex{label: %{type: :and}} = vertex, acc, path) do
    edges = Digraph.out_edges(graph, vertex.id)
    %{true => branches, false => next_edges} = Enum.group_by(edges, &match?(%{label: %{type: :branch}}, &1))

    branch_acc = Enum.reduce(branches, [], &read_plan(graph, Digraph.vertex(graph, &1.v2), &2, []))
    next_acc = Enum.reduce(next_edges, [], &read_plan(graph, Digraph.vertex(graph, &1.v2), &2, []))

    [[{:and, branch_acc, next_acc} | path] | acc]
  end
  def read_plan(graph, %Digraph.Vertex{label: %{type: :or}} = vertex, acc, path) do
    edges = Digraph.out_edges(graph, vertex.id)
    %{true => branches, false => next_edges} = Enum.group_by(edges, &match?(%{label: %{type: :branch}}, &1))

    branch_acc = Enum.reduce(branches, [], &read_plan(graph, Digraph.vertex(graph, &1.v2), &2, []))
    next_acc = Enum.reduce(next_edges, [], &read_plan(graph, Digraph.vertex(graph, &1.v2), &2, []))
    for bpath <- branch_acc, npath <- next_acc do
      Enum.concat([npath, bpath, path])
    end ++ acc
  end
  def read_plan(graph, vertex, acc, path) do
    case Digraph.out_edges(graph, vertex.id) do
      [] -> [[vertex.id | path] | acc]
      edges -> Enum.reduce(edges, acc, &read_plan(graph, Digraph.vertex(graph, &1.v2), &2, [vertex.id | path]))
    end
  end
end
