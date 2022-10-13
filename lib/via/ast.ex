defmodule Via.AST do
  @moduledoc false
  alias Via.AST.{Ident, Join, Params, Prop}
  alias Via.Attr

  @type t :: query() | ast()
  @type ast :: Ident.t() | Join.t() | Params.t() | Prop.t()
  @type recursion :: :... | pos_integer()
  @type query_expr :: :* | ast()
  @type query :: [query_expr()]

  @type prop_expr :: Attr.t() | {atom(), atom()}
  @type ident_expr :: list()
  @type params_expr(key) :: {key, map()}
  @type params_expr :: params_expr(ident_expr() | prop_expr() | join_expr())
  @type join_key :: ident_expr() | prop_expr() | params_expr(ident_expr() | prop_expr())
  @type join_expr :: %{join_key() => [expr(), ...] | recursion()}
  @type expr :: [ident_expr() | prop_expr() | params_expr() | join_expr()]

  @spec from_expr([term()]) :: {:ok, t()} | {:error, reason :: term()}
  def from_expr(expr) do
    expr
    |> Enum.reduce_while({:ok, []}, fn
      :*, {:ok, acc} ->
        {:ok, [:* | acc]}

      x, {:ok, acc} ->
        case parse_expr(x, [&Prop.parse/1, &Ident.parse/1, &Params.parse/1, &Join.parse/1]) do
          {:ok, x} -> {:cont, {:ok, [x | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
    |> case do
      {:ok, query} -> {:ok, :lists.reverse(query)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec to_expr(t()) :: term()
  def to_expr(x)
  def to_expr(data) when is_list(data), do: Enum.map(data, &to_expr/1)
  def to_expr(%Prop{key: attr}), do: attr
  def to_expr(%Ident{prop: p, id: id}), do: [to_expr(p), id]
  def to_expr(%Params{key: k, params: p}), do: {to_expr(k), p}
  def to_expr(%Join{key: k, query: q}), do: %{to_expr(k) => to_expr(q)}
  def to_expr(x) when x in [:*, :...], do: x

  @doc false
  @spec parse_expr(term(), [(term() -> {:ok, ast()} | {:error, reason}), ...]) :: {:ok, ast()} | {:error, reason} when reason: term()
  def parse_expr(expr, parsers) do
    parsers
    |> Enum.reduce_while([], fn f, acc ->
      case f.(expr) do
        {:ok, x} -> {:halt, {:ok, x}}
        {:error, reason} -> {:cont, [reason | acc]}
      end
    end)
    |> case do
      {:ok, x} -> {:ok, x}
      _ -> {:error, {:invalid_expr, expr}}
    end
  end
end
