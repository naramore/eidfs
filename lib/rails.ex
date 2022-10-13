defmodule Rails do
  @moduledoc """
  Partial Railway Oriented Programming implementation in Elixir.

  See this [blog article](https://fsharpforfunandprofit.com/rop/)
  for more details.
  """

  require Logger

  @type ok(a) :: {:ok, a}
  @type fail(a) :: {:error, a}
  @type two_track(a, b) :: ok(a) | fail(b)
  @type two_track_fun(a, b, c, d) :: (two_track(a, b) -> two_track(c, d))
  @type switch_fun(a, b, c) :: (a -> two_track(b, c))
  @type one_track_fun(a, b) :: (a -> b)
  @type chardata_or_fun :: Logger.message() | (() -> Logger.message())

  @typep a :: term()
  @typep b :: term()
  @typep c :: term()
  @typep d :: term()
  @typep e :: term()
  @typep f :: term()
  @typep g :: term()

  # constructors

  @spec ok(a) :: ok(a)
  def ok(a), do: {:ok, a}

  @spec fail(reason) :: fail(reason) when reason: term
  def fail(reason), do: {:error, reason}

  # combiners

  @spec combine(one_track_fun(a, b), one_track_fun(b, c)) :: one_track_fun(a, c)
  def combine(f, g), do: &combine(&1, f, g)

  @spec combine(a, one_track_fun(a, b), one_track_fun(b, c)) :: c
  def combine(x, f, g) do
    x |> f.() |> g.()
  end

  @spec compose(switch_fun(a, b, c), switch_fun(b, d, e)) :: switch_fun(a, d, c | e)
  def compose(f, g), do: &compose(&1, f, g)

  @spec compose(a, switch_fun(a, b, c), switch_fun(b, d, e)) :: two_track(d, c | e)
  def compose(x, f, g) do
    combine(x, f, bind(g))
  end

  @spec plus(switch_fun(a, b, c), switch_fun(a, d, e), (b, d -> f), (c, e -> g)) ::
          switch_fun(a, f, c | e | g)
  def plus(switch1, switch2, add_ok, add_fail),
    do: &plus(&1, switch1, switch2, add_ok, add_fail)

  @spec plus(a, switch_fun(a, b, c), switch_fun(a, d, e), (b, d -> f), (c, e -> g)) ::
          two_track(f, c | e | g)
  def plus(x, switch1, switch2, add_ok, add_fail) do
    case {switch1.(x), switch2.(x)} do
      {{:ok, s1}, {:ok, s2}} -> ok(add_ok.(s1, s2))
      {{:error, f1}, {:ok, _}} -> fail(f1)
      {{:ok, _}, {:error, f2}} -> fail(f2)
      {{:error, f1}, {:error, f2}} -> fail(add_fail.(f1, f2))
    end
  end

  # adapters

  @spec switch(one_track_fun(a, b)) :: switch_fun(a, b, c)
  def switch(f), do: &switch(&1, f)

  @spec switch(any, one_track_fun(a, b)) :: two_track(b, c)
  def switch(x, f), do: combine(x, f, &ok/1)

  @spec bind(switch_fun(a, b, c)) :: two_track_fun(a, d, b, c | d)
  def bind(f), do: &bind(&1, f)

  @spec bind(two_track(a, b), switch_fun(a, c, d)) :: two_track(c, b | d)
  def bind(x, f), do: either(x, f, &fail/1)

  @spec map(one_track_fun(a, b)) :: two_track_fun(a, c, b, c)
  def map(f), do: &map(&1, f)

  @spec map(two_track(a, b), one_track_fun(a, c)) :: two_track(c, b)
  def map(x, f), do: bind(x, switch(f))

  @spec tee(one_track_fun(a, b)) :: one_track_fun(a, a)
  def tee(f), do: &tee(&1, f)

  @spec tee(a, one_track_fun(a, b)) :: a
  def tee(x, f) do
    f.(x)
    x
  end

  @spec safe(one_track_fun(a, b | no_return())) :: switch_fun(a, b, c)
  def safe(f), do: &safe(&1, f)

  @spec safe(a, one_track_fun(a, b | no_return())) :: two_track(b, c)
  def safe(a, f) do
    f.(a)
  rescue
    reason -> {:error, {:raised, reason}}
  catch
    :exit, reason -> {:error, {:exit, reason}}
    x -> {:error, {:caught, x}}
  end

  @spec unsafe(switch_fun(a, b, c)) :: one_track_fun(a, b | no_return())
  def unsafe(f), do: &unsafe(&1, f)

  @spec unsafe(a, switch_fun(a, b, c)) :: b | no_return()
  def unsafe(x, f), do: combine(x, f, either(&id/1, &crash/1))

  @spec bimap(one_track_fun(a, b), one_track_fun(c, d)) :: two_track_fun(a, c, b, d)
  def bimap(on_ok, on_fail), do: &bimap(&1, on_ok, on_fail)

  @spec bimap(two_track(a, c), one_track_fun(a, b), one_track_fun(c, d)) :: two_track(b, d)
  def bimap(x, on_ok, on_fail) do
    either(x, combine(on_ok, &ok/1), combine(on_fail, &fail/1))
  end

  # specialized

  @spec log(two_track(a, b), one_track_fun(a, chardata_or_fun), keyword) :: two_track(a, b)
  def log(two_track, message_fun, metadata \\ []) do
    bimap(
      two_track,
      tee(&Logger.info(message_fun.(&1), metadata)),
      tee(&Logger.error(fn -> error_message(&1) end, metadata))
    )
  end

  @spec reduce_while([two_track(a, b)], two_track(c, d), switch_fun({a, c}, c, d)) ::
          two_track(c, b | d)
  def reduce_while(two_tracks, acc, fun) do
    Enum.reduce_while(two_tracks, acc, fn
      _, {:error, reason} ->
        {:halt, fail(reason)}

      {:error, reason}, _ ->
        {:halt, fail(reason)}

      {:ok, x}, {:ok, acc} ->
        {:cont, fun.({x, acc})}
    end)
  end

  @spec reduce([two_track(a, b)], two_track(c, d), switch_fun({a, c}, c, d)) ::
          two_track(c, [b | d])
  def reduce(two_tracks, acc, fun) do
    Enum.reduce(two_tracks, acc, fn
      {:error, reason}, {:ok, _} ->
        fail([reason])

      {:error, reason}, {:error, reasons} ->
        fail([reason | reasons])

      {:ok, _}, {:error, reasons} ->
        fail(reasons)

      {:ok, x}, {:ok, acc} ->
        fun.({x, acc})
    end)
  end

  @spec extract([two_track(a, b)]) :: two_track([a], b)
  def extract(two_tracks) do
    reduce_while(two_tracks, ok([]), switch(&id/1))
  end

  # misc

  @spec either((a -> c), (b -> d)) :: c | d
  def either(on_ok, on_fail), do: &either(&1, on_ok, on_fail)

  @spec either(two_track(a, b) | term, (a -> c), (b -> d)) :: c | d
  def either(x, on_ok, on_fail)
  def either({:ok, x}, on_ok, _on_fail), do: on_ok.(x)
  def either({:error, reason}, _on_ok, on_fail), do: on_fail.(reason)
  def either(x, _on_ok, _on_fail), do: {:error, {:expected_two_track, x}}

  @spec id(a) :: a
  def id(x), do: x

  @spec keep(a, b) :: a
  def keep(x, _), do: x

  @spec accumulate(a, b) :: [...]
  def accumulate(x, y)
  def accumulate(x, y) when is_list(x) and is_list(y), do: x ++ y
  def accumulate(x, y) when is_list(x), do: x ++ [y]
  def accumulate(x, y) when is_list(y), do: [x | y]
  def accumulate(x, y), do: [x, y]

  @spec curry(fun) :: fun
  def curry(fun) do
    {_, arity} = :erlang.fun_info(fun, :arity)
    curry(fun, arity, [])
  end

  # helpers

  @spec curry(fun, integer, [any]) :: fun
  defp curry(fun, 0, arguments), do: apply(fun, Enum.reverse(arguments))

  defp curry(fun, arity, arguments) do
    fn arg -> curry(fun, arity - 1, [arg | arguments]) end
  end

  @spec error_message(reason :: term) :: Logger.message()
  defp error_message(reason)

  defp error_message(%{__exception__: true} = error) do
    Exception.format(:error, error, [])
  end

  defp error_message(reason) do
    case String.Chars.impl_for(reason) do
      nil -> inspect(reason)
      otherwise -> to_string(otherwise)
    end
  end

  @spec crash(a) :: no_return()
  defp crash(term)
  defp crash({:caught, x}), do: throw(x)
  defp crash({:exit, reason}), do: exit(reason)
  defp crash({:raised, reason}), do: raise(reason)
  defp crash(reason), do: raise(reason)
end
