defmodule Hijack.Context do
  @moduledoc false

  alias Hijack.Error
  alias Hijack.Pipe
  alias Hijack.Stage

  @container :__pipe__
  @error :__error__

  @type id :: any()
  @type error :: any()
  @type container :: Pipe.t()
  @type direction :: Pipe.direction() | :error
  @type t :: %{
          :__pipe__ => container() | nil,
          :__error__ => error() | nil,
          optional(any) => any()
        }

  @spec new(map()) :: t()
  def new(data \\ %{}) do
    Map.merge(
      %{
        @container => Pipe.new(),
        @error => nil
      },
      data
    )
  end

  @spec enter(t) :: t
  def enter(context) do
    context
    |> Map.put(@error, nil)
    |> update_container(&Pipe.enter/1)
  end

  @spec leave(t) :: t
  def leave(context) do
    context
    |> Map.put(@error, nil)
    |> update_container(&Pipe.leave/1)
  end

  @spec error(t, error(), Error.type()) :: t
  def error(context, reason, type \\ :error) do
    context
    |> Map.put(@error, Error.wrap(context, reason, type))
    |> update_container(&Pipe.leave/1)
  end

  @spec execute(t) :: t
  def execute(context) do
    case step(context) do
      {:cont, context} -> execute(context)
      {:halt, context} -> context
    end
  end

  @spec step(t) :: {:cont, t} | {:halt, t}
  def step(context) do
    case Pipe.peek(Map.get(context, @container)) do
      {:ok, stage} ->
        before = get_direction(context)
        context = Stage.invoke(stage, context)

        if before == get_direction(context) do
          next(context)
        else
          {:cont, context}
        end

      :error ->
        {:halt, context}
    end
  end

  @spec enqueue(t, [Stage.t()]) :: t
  def enqueue(context, stages) do
    update_container(context, &Pipe.enqueue(&1, stages))
  end

  @spec cons(t, [Stage.t()]) :: t
  def cons(context, stages) do
    update_container(context, &Pipe.enqueue(&1, stages))
  end

  @spec dequeue(t, pos_integer) :: t
  def dequeue(context, num \\ 1) do
    update_container(context, &Pipe.dequeue(&1, num))
  end

  @spec drop(t, pos_integer) :: t
  def drop(context, num \\ 1) do
    update_container(context, &Pipe.drop(&1, num))
  end

  @spec terminate(t) :: t
  def terminate(context) do
    update_container(context, &Pipe.terminate/1)
  end

  @spec halt(t) :: t
  def halt(context) do
    update_container(context, &Pipe.halt/1)
  end

  @spec retry(t) :: t
  def retry(context) do
    update_container(context, &Pipe.retry/1)
  end

  @spec skip(t, pos_integer) :: t
  def skip(context, num \\ 1) do
    update_container(context, &Pipe.skip(&1, num))
  end

  @doc false
  @spec get_stage(t) :: id | nil
  def get_stage(%{@container => container}) do
    case Pipe.peek(container) do
      {:ok, %{id: id}} -> id
      _ -> nil
    end
  end

  def get_stage(_), do: nil

  @doc false
  @spec get_direction(t) :: direction
  def get_direction(%{@error => nil, @container => container}) do
    Pipe.get_direction(container)
  end

  def get_direction(_), do: :error

  @doc false
  @spec get_error(t) :: error | nil
  def get_error(context) do
    Map.get(context, @error)
  end

  @spec update_container(t, (container -> container)) :: t
  defp update_container(context, fun) do
    context
    |> prep_context()
    |> Map.update!(@container, fun)
  end

  @spec next(t) :: {:cont, t} | {:halt, t}
  defp next(context) do
    with %{@container => pipe} = context <- prep_context(context),
         {:ok, pipe} <- Pipe.next(pipe) do
      {:cont, Map.put(context, @container, pipe)}
    else
      _ -> {:halt, context}
    end
  end

  @spec prep_context(t) :: t
  defp prep_context(context) do
    case Map.fetch(context, @container) do
      :error -> new(context)
      {:ok, nil} -> new(context)
      {:ok, _pipe} -> context
    end
  end
end
