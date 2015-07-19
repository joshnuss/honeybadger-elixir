defmodule Honeybadger.Logger do
  require Logger
  alias Honeybadger.Utils

  @exception_format ~r/\((?<exception>.*?)\) (?<message>(.*))/
  @ignored_keys [:pid, :function, :line, :module]

  use GenEvent

  def init(_mod), do: {:ok, []}

  def handle_call({:configure, new_keys}, _state) do
    {:ok, :ok, new_keys}
  end

  def handle_event({level, _gl, _event}, state)
  when level != :error do
    {:ok, state}
  end

  def handle_event({_level, gl, _event}, state)
  when node(gl) != node() do
    {:ok, state}
  end

  # Error messages from Ranch/Cowboy come in the form of iodata. We ignore
  # these because they should already be reported by Honeybadger.Plug.
  def handle_event({:error, _gl, {_mod, message, _ts, _pdict}}, state) 
  when is_list(message) do
    {:ok, state}
  end

  def handle_event({:error, _gl, {Logger, message, _ts, pdict}}, state) do
    try do
      exception = exception_from_message(message)
      context = Dict.drop(pdict, @ignored_keys) |> Enum.into(Map.new)
      Honeybadger.notify exception, context, System.stacktrace
    rescue
      ex ->
        error_type = Utils.strip_elixir_prefix(ex.__struct__)
        message = "Unable to notify Honeybadger! #{error_type}: #{ex.message}"
        Logger.warn(message)
    end

    {:ok, state}
  end

  defp exception_from_message(message) do
    error = Regex.named_captures @exception_format, message
    type = error["exception"]
    |> String.split(".") 
    |> Module.safe_concat

    struct type, Dict.drop(error, ["exception"])
  end
end
