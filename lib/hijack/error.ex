defmodule Hijack.Error do
  @moduledoc false

  alias Hijack.Context

  @derive {Inspect, only: [:type, :reason, :stage, :direction]}
  defexception type: :raise,
               reason: nil,
               stage: nil,
               direction: :enter,
               trace: []

  @type t :: %__MODULE__{
          type: type,
          reason: reason,
          stage: Hijack.id(),
          direction: Hijack.direction(),
          trace: [t]
        }

  @type reason :: term
  @type type :: :error | :raise | :exit | :throw | :timeout

  @impl Exception
  def message(%__MODULE__{reason: reason}) do
    # TODO: update this...
    inspect(reason)
  end

  @spec new(reason, keyword) :: t
  def new(reason, opts \\ []) do
    %__MODULE__{
      type: Keyword.get(opts, :type, :raise),
      reason: reason,
      stage: Keyword.get(opts, :id),
      direction: Keyword.get(opts, :direction, :enter),
      trace: Keyword.get(opts, :trace, [])
    }
  end

  @spec from(term, reason, keyword) :: t
  def from(error, reason, opts \\ [])

  def from(%__MODULE__{} = error, error, _opts) do
    error
  end

  def from(%__MODULE__{} = error, %__MODULE__{} = reason, _opts) do
    Map.put(reason, :trace, [%{error | trace: []} | reason.trace] ++ error.trace)
  end

  def from(%__MODULE__{} = error, reason, opts) do
    reason
    |> new(opts)
    |> Map.put(:trace, [%{error | trace: []} | error.trace])
  end

  def from(error, %__MODULE__{} = reason, _opts) do
    Map.put(reason, :trace, [error | reason.trace])
  end

  def from(error, reason, opts) do
    reason
    |> new(opts)
    |> Map.put(:trace, [new(error)])
  end

  @spec wrap(Hijack.context(), Hijack.error(), type) :: t
  def wrap(context, reason, type \\ :error) do
    case Context.get_error(context) do
      nil ->
        new(reason, gen_opts(context, type))

      error ->
        from(error, reason, gen_opts(context, type))
    end
  end

  @spec gen_opts(Hijack.context(), type) :: keyword
  defp gen_opts(context, type) do
    [
      type: type,
      id: Context.get_stage(context),
      direction: Context.get_direction(context)
    ]
  end
end

defmodule Hijack.ConditionError do
  @moduledoc false

  defexception type: nil,
               id: nil,
               reason: nil

  @type t :: %__MODULE__{
          type: atom,
          id: Hijack.id(),
          reason: term()
        }

  @impl Exception
  def message(%__MODULE__{type: type, id: id, reason: reason}) do
    "type=#{type} id=#{id} #{inspect(reason)}"
  end

  @spec new(keyword) :: t
  def new(opts \\ []) do
    %__MODULE__{
      type: Keyword.get(opts, :type),
      id: Keyword.get(opts, :id),
      reason: Keyword.get(opts, :reason)
    }
  end
end
