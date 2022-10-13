defmodule Hijack.Pipe do
  @moduledoc false

  alias Hijack.Stage

  defstruct queue: :queue.new(),
            stack: [],
            direction: :enter

  @type t :: %__MODULE__{
          queue: :queue.queue(Stage.t()),
          stack: [Stage.t()],
          direction: direction
        }

  @type direction :: :enter | :leave

  @spec new([Stage.t()], direction) :: t
  def new(stages \\ [], direction \\ :enter) do
    %__MODULE__{
      queue: :queue.from_list(stages),
      direction: direction
    }
  end

  @spec get_direction(t) :: direction()
  def get_direction(pipe), do: pipe.direction

  @spec peek(t) :: {:ok, Stage.t()} | :error
  def peek(pipe)

  def peek(%__MODULE__{direction: :enter, queue: q}) do
    case :queue.peek(q) do
      {:value, x} -> {:ok, x}
      _ -> :error
    end
  end

  def peek(%__MODULE__{direction: :leave, stack: [x | _]}) do
    {:ok, x}
  end

  def peek(%__MODULE__{stack: []}) do
    :error
  end

  @spec peek_next(t) :: {:ok, Stage.t()} | :error
  def peek_next(pipe) do
    case pop(pipe) do
      {stage, _} -> {:ok, stage}
      _ -> :error
    end
  end

  @spec pop(t) :: {Stage.t(), t} | nil
  def pop(pipe) do
    with {:ok, x} <- peek(pipe),
         {:ok, pipe} <- next(pipe) do
      {x, pipe}
    else
      _ -> nil
    end
  end

  @spec next(t) :: {:ok, t} | :error
  def next(pipe)

  def next(%__MODULE__{direction: :enter, queue: q, stack: s} = pipe) do
    with {{:value, x}, q} <- :queue.out(q),
         {_, false} <- {x, :queue.is_empty(q)} do
      {:ok, %{pipe | queue: q, stack: [x | s]}}
    else
      {:empty, _} ->
        next(%{pipe | direction: :leave})

      {x, true} ->
        pipe
        |> Map.put(:queue, :queue.new())
        |> Map.put(:stack, [x | s])
        |> Map.put(:direction, :leave)
        |> then(&{:ok, &1})
    end
  end

  def next(%__MODULE__{direction: :leave, queue: q, stack: [x | xs]} = pipe) do
    {:ok, %{pipe | queue: :queue.cons(x, q), stack: xs}}
  end

  def next(%__MODULE__{direction: :leave, stack: []}), do: :error

  @spec previous(t) :: {:ok, t} | :error
  def previous(pipe) do
    pipe
    |> flip_direction()
    |> next()
    |> case do
      {:ok, %{queue: q} = pipe} ->
        if :queue.len(q) == 0 do
          {:ok, pipe}
        else
          {:ok, flip_direction(pipe)}
        end

      otherwise ->
        otherwise
    end
  end

  @spec enqueue(t, [Stage.t()]) :: t
  def enqueue(pipe, stages)

  def enqueue(%__MODULE__{direction: :enter} = pipe, stages) do
    Map.update!(pipe, :queue, fn q ->
      :queue.join(q, :queue.from_list(stages))
    end)
  end

  def enqueue(%__MODULE__{direction: :leave} = pipe, stages) do
    Map.update!(pipe, :stack, fn s -> s ++ stages end)
  end

  @spec cons(t, [Stage.t()]) :: t
  def cons(pipe, stages)

  def cons(%__MODULE__{direction: :enter} = pipe, stages) do
    Map.update!(pipe, :queue, fn q ->
      :queue.join(:queue.from_list(stages), q)
    end)
  end

  def cons(%__MODULE__{direction: :leave} = pipe, stages) do
    Map.update!(pipe, :stack, fn s -> stages ++ s end)
  end

  @spec dequeue(t, pos_integer) :: t
  def dequeue(pipe, num \\ 1)

  def dequeue(%__MODULE__{direction: :enter} = pipe, num) do
    Map.update!(pipe, :queue, fn q -> mdrop(q, num, &:queue.drop_r/1) end)
  end

  def dequeue(%__MODULE__{direction: :leave} = pipe, num) do
    Map.update!(pipe, :stack, &Enum.reverse(Enum.drop(Enum.reverse(&1), num)))
  end

  @spec drop(t, pos_integer) :: t
  def drop(pipe, num \\ 1)

  def drop(%__MODULE__{direction: :enter} = pipe, num) do
    Map.update!(pipe, :queue, fn q -> mdrop(q, num, &:queue.drop/1) end)
  end

  def drop(%__MODULE__{direction: :leave} = pipe, num) do
    Map.update!(pipe, :stack, &Enum.drop(&1, num))
  end

  @spec enter(t) :: t
  def enter(pipe) do
    Map.put(pipe, :direction, :enter)
  end

  @spec leave(t) :: t
  def leave(pipe) do
    Map.put(pipe, :direction, :leave)
  end

  @spec terminate(t) :: t
  def terminate(pipe) do
    Map.put(pipe, :queue, :queue.new())
  end

  @spec halt(t) :: t
  def halt(pipe) do
    pipe
    |> terminate()
    |> Map.put(:stack, [])
  end

  @spec retry(t) :: t
  def retry(pipe) do
    case previous(pipe) do
      {:ok, pipe} -> pipe
      _ -> pipe
    end
  end

  @spec skip(t, pos_integer) :: t
  def skip(pipe, num \\ 1)
  def skip(pipe, num) when num <= 0, do: pipe

  def skip(pipe, num) do
    case next(pipe) do
      {:ok, pipe} -> skip(pipe, num - 1)
      _ -> pipe
    end
  end

  @spec flip_direction(t) :: t
  defp flip_direction(pipe)
  defp flip_direction(%{direction: :enter} = pipe), do: Map.put(pipe, :direction, :leave)
  defp flip_direction(%{direction: :leave} = pipe), do: Map.put(pipe, :direction, :enter)

  @spec mdrop(:queue.queue(), pos_integer, (:queue.queue() -> :queue.queue())) :: :queue.queue()
  defp mdrop(queue, num, drop_fun) do
    Enum.reduce_while(1..num, queue, fn _, q ->
      if :queue.is_empty(q) do
        {:halt, q}
      else
        {:cont, drop_fun.(q)}
      end
    end)
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(pipe, opts) do
      coll =
        List.flatten([
          :lists.reverse(pipe.stack),
          get_direction(pipe),
          :queue.to_list(pipe.queue)
        ])

      container_doc("#Pipe<[ ", coll, " ]>", opts, &inspect_impl/2, break: :flex, separator: "")
    end

    defp inspect_impl(data, _opts) when is_binary(data), do: string(data)
    defp inspect_impl(data, opts), do: @protocol.inspect(data, opts)

    defp get_direction(%@for{direction: :enter}), do: "|>"
    defp get_direction(%@for{direction: :leave}), do: "<|"
  end
end
