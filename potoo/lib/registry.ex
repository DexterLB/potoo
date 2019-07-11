defmodule Potoo.Registry do
  use GenServer
  require Logger

  def start_link(static_data, opts \\ []) do
    GenServer.start_link(__MODULE__, static_data, opts)
  end

  def init(static_data) do
    case Potoo.Channel.start_link() do
      {:ok, chan} ->
        {:ok, {static_data, %{}, chan}}
      err -> err
    end
  end

  def handle_call(:contract, _from, state) do
    {:reply, contract(state), state}
  end

  def handle_call(:subscribe_contract, _from, state = {_, _, contract_channel}) do
    {:reply, contract_channel, state}
  end

  def handle_call({"register", %{"name" => name, "delegate" => delegate}}, _from, {static_data, services, contract_channel}) do
    remote_monitor(delegate.destination, name)

    Logger.debug fn ->
      "registering #{name} (#{inspect(delegate.destination)}) to registry #{inspect(self())}"
    end

    new_state = {static_data, register(services, name, delegate), contract_channel}
    Potoo.Channel.send_lazy(contract_channel, fn -> contract(new_state) end)
    {:reply, :ok, new_state}
  end

  def handle_call({"deregister", %{"name" => name}}, _from, {static_data, services, contract_channel}) do
    Logger.debug fn ->
      "unregistering #{name} from registry #{inspect(self())}"
    end

    new_state = {static_data, deregister(services, name), contract_channel}
    Potoo.Channel.send_lazy(contract_channel, fn -> contract(new_state) end)
    {:reply, :ok, new_state}
  end

  defp register(services, name, delegate) do
    Map.put(services, name, delegate)
  end

  defp deregister(services, name) do
    Map.delete(services, name)
  end

  defp remote_monitor(target, name) do
    from = self()

    spawn_link(
      fn() ->
        Process.monitor(target)
        receive_downs(from, name)
      end
    )
  end

  defp receive_downs(from, name) do
    receive do
      {:DOWN, _, :process, _, _} ->
        GenServer.call(from, {"deregister", %{"name" => name}})
      msg ->
        Logger.debug(fn ->
          "unknown monitor message: #{inspect(msg)}"
        end)
        receive_downs(from, name)
    end
  end

  defp contract({static_data, services, _}) do
    Map.merge(
      static_data,
      %{
        "register" => %Potoo.Contract.Function{
          name: "register",
          argument: {:struct, %{
            "name" => {:type,
              :string,
              %{"description" => "Unique name for the service"}
            },
            "delegate" => :delegate
          }},
          retval: {:union,
            {:literal, :ok},
            {:struct, {{:literal, :error}, :string}}
          },
          data: %{
            "description" => "Registers a new service into the registry",
            "ui_tags" => "level:2"
          }
        },
        "deregister" => %Potoo.Contract.Function{
          name: "deregister",
          argument: {:struct, %{
            "name" => {:type,
              :string,
              %{"description" => "Unique name of the service to be deregistered"}
            }
          }},
          retval: {:union,
            {:literal, :ok},
            {:struct, {{:literal, :error}, :string}}
          },
          data: %{
            "description" => "Deregisters a service from the registry",
            "ui_tags" => "level:2"
          }
        },
        "services" => services
      }
    )
  end
end