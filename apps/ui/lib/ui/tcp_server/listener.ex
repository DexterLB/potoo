defmodule Ui.TcpServer.Listener do
  use GenServer
  require Logger

  @behaviour :ranch_protocol

  def start_link(ref, socket, transport, opts \\ []) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [ref, socket, transport, opts])
    {:ok, pid}
  end

  def init(ref, socket, transport, opts) do
    Logger.debug(fn -> ["start tcp listener: ", inspect(socket)] end)

    :ok = :ranch.accept_ack(ref)
    :ok = transport.setopts(socket, [{:active, true}])
    {:ok, handler_state} = Ui.TcpServer.Handler.init(opts)
    :gen_server.enter_loop(__MODULE__, opts, %{socket: socket, transport: transport, handler_state: handler_state})
  end

  def handle_info({:tcp, socket, data}, state = %{socket: socket, handler_state: handler_state}) do
    Logger.debug(fn -> ["tcp [", inspect(socket), "] -> ", inspect(data)] end)

    Ui.TcpServer.Handler.socket_handle({:text, data}, handler_state)
      |> handler_reply(state)
  end
  def handle_info({:tcp_closed, socket}, state = %{socket: socket, transport: transport}) do
    Logger.debug(fn -> ["closing tcp listener: ", inspect(socket)] end)

    transport.close(socket)
    {:stop, :normal, state}
  end
  def handle_info(info, state = %{handler_state: handler_state}) do
    Ui.TcpServer.Handler.socket_info(info, handler_state)
      |> handler_reply(state)
  end

  defp handler_reply(reply, state = %{socket: socket, transport: transport}) do
    new_state = case reply do
      {:reply, reply, new_state} ->
        Logger.debug(fn -> ["tcp [", inspect(socket), "] <- ", inspect(reply)] end)
        transport.send(socket, reply)
        new_state
      {:noreply, new_state} -> new_state
    end

    {:noreply, %{state | handler_state: new_state}}
  end
end