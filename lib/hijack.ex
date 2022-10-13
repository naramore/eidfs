defmodule Hijack do
  @moduledoc false

  alias Hijack.ConditionError
  alias Hijack.Context
  alias Hijack.Error
  alias Hijack.Stage

  @type id :: Context.id()
  @type error :: Context.error()
  @type direction :: Context.direction()
  @type context :: Context.t()

  defdelegate start(context \\ %{}), to: Context, as: :new
  defdelegate execute(context), to: Context
  defdelegate step(context), to: Context
  defdelegate enter(context), to: Context
  defdelegate leave(context), to: Context
  defdelegate error(context, error), to: Context
  defdelegate enqueue(context, stages), to: Context
  defdelegate cons(context, stages), to: Context
  defdelegate dequeue(context, num \\ 1), to: Context
  defdelegate drop(context, num \\ 1), to: Context
  defdelegate terminate(context), to: Context
  defdelegate halt(context), to: Context
  defdelegate retry(context), to: Context
  defdelegate skip(context, num \\ 1), to: Context

  @spec stage(keyword) :: Stage.t()
  def stage(opts \\ []) do
    case Keyword.pop(opts, :module) do
      {nil, opts} -> Stage.new(opts)
      {module, opts} -> Stage.from_module(module, opts)
    end
  end

  @spec stage(context(), keyword) :: context()
  def stage(context, opts) do
    enqueue(context, [stage(opts)])
  end

  @spec execute(context(), [Stage.t()]) :: context()
  def execute(context, stages) do
    context
    |> enqueue(stages)
    |> execute()
  end

  @spec transform(Stage.stage_fun(), (context, any -> context)) :: Stage.stage_fun()
  def transform(f, g) do
    fn context ->
      g.(context, f.(context))
    end
  end

  @spec take_in(Stage.stage_fun(), path :: [term, ...]) :: Stage.stage_fun()
  def take_in(f, path) do
    fn context ->
      f.(get_in(context, path))
    end
  end

  @spec return_at(Stage.stage_fun(), path :: [term, ...]) :: Stage.stage_fun()
  def return_at(f, path) do
    transform(f, &put_in(&1, path, &2))
  end

  @spec whenever(Stage.stage_fun(), (context -> boolean)) :: Stage.stage_fun()
  def whenever(f, pred) do
    fn context ->
      if pred.(context) do
        f.(context)
      else
        context
      end
    end
  end

  @spec lens(Stage.stage_fun(), path :: [term, ...]) :: Stage.stage_fun()
  def lens(f, path) do
    f
    |> take_in(path)
    |> return_at(path)
  end

  @spec discard(Stage.stage_fun()) :: Stage.stage_fun()
  def discard(f) do
    transform(f, fn context, _ -> context end)
  end

  @spec timeout(Stage.stage_fun(), timeout) :: Stage.stage_fun()
  def timeout(f, timeout \\ :infinity) do
    fn ctx ->
      task = Task.async(fn -> f.(ctx) end)

      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, context} -> context
        {:exit, reason} -> error(ctx, Error.wrap(ctx, reason, :exit))
        _ -> error(ctx, Error.wrap(ctx, {:timeout, timeout}, :timeout))
      end
    end
  end

  @spec match(Macro.t()) :: Macro.t()
  defmacro match(pattern) do
    quote do
      fn ctx ->
        if match?(unquote(pattern), ctx) do
          :ok
        else
          {:error, {:no_match, unquote(pattern)}}
        end
      end
    end
  end

  @spec exists([term, ...]) :: (context -> :ok | {:error, reason :: term})
  def exists(path) do
    fn ctx ->
      case get_in(ctx, path) do
        nil -> {:error, {:path_not_found, path}}
        _ -> :ok
      end
    end
  end

  @spec requires(Stage.stage_fun(), id, (context -> :ok | :error | {:error, reason :: term})) ::
          Stage.stage_fun()
  def requires(f, id, predicate) do
    fn ctx ->
      process_predicate(predicate.(ctx), ctx, id, :requires, f)
    end
  end

  @spec provides(Stage.stage_fun(), id, (context -> :ok | :error | {:error, reason :: term})) ::
          Stage.stage_fun()
  def provides(f, id, predicate) do
    fn ctx ->
      ctx = f.(ctx)
      process_predicate(predicate.(ctx), ctx, id, :provides)
    end
  end

  @spec satisfies(
          Stage.stage_fun(),
          id,
          (context, context -> :ok | :error | {:error, reason :: term})
        ) :: Stage.stage_fun()
  def satisfies(f, id, predicate) do
    fn ctx ->
      new_ctx = f.(ctx)
      process_predicate(predicate.(ctx, new_ctx), new_ctx, id, :satisfies)
    end
  end

  @spec process_predicate(
          :ok | :error | {:error, reason :: term},
          context,
          id,
          atom,
          (context -> context)
        ) :: context
  defp process_predicate(result, ctx, id, type, on_ok \\ fn x -> x end)
  defp process_predicate(:ok, ctx, _id, _type, on_ok), do: on_ok.(ctx)

  defp process_predicate(:error, ctx, id, type, on_ok),
    do: process_predicate({:error, "predicate unsatisfied"}, ctx, id, type, on_ok)

  defp process_predicate({:error, reason}, ctx, id, type, _on_ok),
    do: error(ctx, ConditionError.new(id: id, type: type, reason: reason))
end
