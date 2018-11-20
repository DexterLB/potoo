defmodule PotooTest do
  use ExUnit.Case
  doctest Potoo

  defmodule PotooTest.FooService do
    use GenServer

    @contract %{
      "description" => "A service which provides a greeting.",
      "methods" => %{
        "hello" => %Potoo.Contract.Function{
          name: "methods.hello",
          argument: {:struct, %{
            "item" => {:type, :string, %{
              "description" => "item to greet"
            }}
          }},
          retval: :string,
          data: %{
            "description" => "Performs a greeting"
          }
        }
      }
    }

    def init(state) do
      {:ok, state}
    end

    def handle_call(:contract, _from, state) do
      {:reply, @contract, state}
    end

    def handle_call(:subscribe_contract, _from, state) do
      {:reply, @contract, state}
    end

    def handle_call({"methods.hello", %{"item" => item}}, _, state) do
      {:reply, "Hello, #{item}!", state}
    end
  end

  test "can call function from contract" do
    {:ok, pid} = GenServer.start_link(PotooTest.FooService, nil)

    contract = Potoo.get_contract(pid)

    hello = Kernel.get_in(contract, ["methods", "hello"])

    assert hello != nil

    assert Potoo.call(pid, hello, %{"item" => "foo"}) == "Hello, foo!"
  end

  test "can call function from pidless contract" do
    {:ok, pid} = GenServer.start_link(PotooTest.FooService, nil)

    contract = Potoo.get_contract_pidless(pid)

    hello = Kernel.get_in(contract, ["methods", "hello"])

    assert hello != nil

    assert Potoo.call(pid, hello, %{"item" => "foo"}) == "Hello, foo!"
  end

  test "can call function from pidless contract by delegate" do
    {:ok, pid} = GenServer.start_link(PotooTest.FooService, nil)

    contract = Potoo.get_contract_pidless(pid)

    hello = Kernel.get_in(contract, ["methods", "hello"])

    assert hello != nil

    delegate = %Potoo.Contract.Delegate{destination: pid}

    assert Potoo.call(delegate, hello, %{"item" => "foo"}) == "Hello, foo!"
  end

  test "can call function from contract without supplying pid" do
    {:ok, pid} = GenServer.start_link(PotooTest.FooService, nil)

    contract = Potoo.get_contract(pid)

    hello = Kernel.get_in(contract, ["methods", "hello"])

    assert hello != nil

    assert Potoo.call(hello, %{"item" => "foo"}) == "Hello, foo!"
  end

  test "can call function unsafely from contract" do
    {:ok, pid} = GenServer.start_link(PotooTest.FooService, nil)

    contract = Potoo.get_contract(pid)

    hello = Kernel.get_in(contract, ["methods", "hello"])

    assert hello != nil

    assert Potoo.unsafe_call(pid, hello, %{"item" => "foo"}) == "Hello, foo!"
  end

  test "can call function unsafely from pidless contract by delegate" do
    {:ok, pid} = GenServer.start_link(PotooTest.FooService, nil)

    contract = Potoo.get_contract_pidless(pid)

    hello = Kernel.get_in(contract, ["methods", "hello"])

    assert hello != nil

    delegate = %Potoo.Contract.Delegate{destination: pid}

    assert Potoo.unsafe_call(delegate, hello, %{"item" => "foo"}) == "Hello, foo!"
  end

  test "can call function unsafely from pidless contract" do
    {:ok, pid} = GenServer.start_link(PotooTest.FooService, nil)

    contract = Potoo.get_contract_pidless(pid)

    hello = Kernel.get_in(contract, ["methods", "hello"])

    assert hello != nil

    assert Potoo.unsafe_call(pid, hello, %{"item" => "foo"}) == "Hello, foo!"
  end

  test "can call function unsafely from contract without supplying pid" do
    {:ok, pid} = GenServer.start_link(PotooTest.FooService, nil)

    contract = Potoo.get_contract(pid)

    hello = Kernel.get_in(contract, ["methods", "hello"])

    assert hello != nil

    assert Potoo.unsafe_call(hello, %{"item" => "foo"}) == "Hello, foo!"
  end

  test "can call function by name (unsafe call)" do
    {:ok, pid} = GenServer.start_link(PotooTest.FooService, nil)

    contract = Potoo.get_contract(pid)

    hello = Kernel.get_in(contract, ["methods", "hello"])

    assert hello != nil

    assert Potoo.unsafe_call(pid, hello.name, %{"item" => "foo"}) == "Hello, foo!"
  end

  test "can call function with deep call" do
    {:ok, pid} = GenServer.start_link(PotooTest.FooService, nil)

    assert Potoo.deep_call(pid, ["methods", "hello"], %{"item" => "foo"})
      == "Hello, foo!"
  end
end