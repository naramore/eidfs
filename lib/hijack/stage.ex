defmodule Hijack.Stage do
  @moduledoc false

  alias Hijack.Context

  @default_type :unsafe

  defstruct id: nil,
            enter: nil,
            leave: nil,
            error: nil,
            type: @default_type

  @type t :: %__MODULE__{
          id: id,
          enter: stage_fun | nil,
          leave: stage_fun | nil,
          error: error_fun | nil,
          type: type
        }

  @type id :: Hijack.id()
  @type context :: Hijack.context()
  @type error :: Hijack.error()
  @type stage_fun :: (context() -> context())
  @type error_fun :: (context(), error() -> context())
  @type type :: :safe | :idempotent | :unsafe

  @callback enter(context()) :: context()
  @callback leave(context()) :: context()
  @callback error(context(), error()) :: context()

  @spec new(keyword) :: t
  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id),
      enter: Keyword.get(opts, :enter),
      leave: Keyword.get(opts, :leave),
      error: Keyword.get(opts, :error),
      type: Keyword.get(opts, :type, @default_type)
    }
  end

  @spec from_function(stage_fun(), keyword) :: t
  def from_function(fun, opts \\ []) do
    opts
    |> Keyword.put(:enter, fun)
    |> new()
  end

  @spec from_map(map) :: t
  def from_map(data) do
    data
    |> Enum.into([])
    |> new()
  end

  @spec from_module(module, keyword) :: t
  def from_module(module, opts \\ []) do
    new(
      id: Keyword.get(opts, :id, module),
      enter: &module.enter/1,
      leave: &module.leave/1,
      error: &module.error/2,
      type: Keyword.get(opts, :type, @default_type)
    )
  end

  @spec invoke(t, context()) :: context()
  def invoke(stage, context) do
    context
    |> Context.get_direction()
    |> maybe_add_error(context)
    |> extract(stage)
    |> safe_invoke(context)
  end

  @spec maybe_add_error(Context.direction(), context()) :: :enter | :leave | {:error, error()}
  defp maybe_add_error(:error, context), do: {:error, Context.get_error(context)}
  defp maybe_add_error(direction, _context), do: direction

  @spec extract(:enter | :leave | {:error, error()}, t) :: stage_fun()
  defp extract(:enter, %{enter: nil}), do: &id/1
  defp extract(:enter, stage), do: stage.enter
  defp extract(:leave, %{leave: nil}), do: &id/1
  defp extract(:leave, stage), do: stage.leave
  defp extract({:error, _reason}, %{error: nil}), do: &id/1
  defp extract({:error, reason}, stage), do: &stage.error.(&1, reason)

  @spec safe_invoke(stage_fun(), context()) :: context()
  defp safe_invoke(fun, context) do
    fun.(context)
  rescue
    error -> Context.error(context, error, :raise)
  catch
    :exit, reason -> Context.error(context, reason, :exit)
    value -> Context.error(context, value, :throw)
  end

  @spec id(context()) :: context()
  defp id(ctx), do: ctx

  @doc false
  defmacro __using__(opts) do
    default_module = Keyword.get(opts, :default)

    if is_nil(default_module) do
      quote do
        @behaviour Hijack.Stage

        @impl Hijack.Stage
        def enter(context) do
          context
        end

        @impl Hijack.Stage
        def leave(context) do
          context
        end

        @impl Hijack.Stage
        def error(context, _error) do
          context
        end

        defoverridable enter: 1, leave: 1, error: 2
      end
    else
      quote do
        @default_module unquote(default_module)
        @behaviour Hijack.Stage

        @impl Hijack.Stage
        def enter(context) do
          @default_module.enter(context)
        end

        @impl Hijack.Stage
        def leave(context) do
          @default_module.leave(context)
        end

        @impl Hijack.Stage
        def error(context, error) do
          @default_module.error(context, error)
        end

        defoverridable enter: 1, leave: 1, error: 2
      end
    end
  end

  defimpl Inspect do
    def inspect(stage, _opts) do
      "#Stage<id: #{stage.id}>"
    end
  end
end
