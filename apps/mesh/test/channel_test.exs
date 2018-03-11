defmodule Mesh.ChannelTest do
  use ExUnit.Case
  doctest Mesh.Channel

  alias Mesh.Channel

  test "item returned by start_link is a channel" do
    {:ok, ch} = Channel.start_link()

    assert Channel.is_channel(ch) == true
  end

  test "suspicious things are not channels" do
    assert Channel.is_channel((fn() -> 42 end).()) == false
    assert Channel.is_channel({Mesh.Channel, 42}) == false
  end

  test "can use channel to send a message to one recipient" do
    {:ok, ch} = Channel.start_link()

    :ok = Channel.subscribe(ch, self(), :foo)

    spawn(fn() -> Channel.send(ch, 42) end)

    assert_receive({:foo, 42})
  end

  test "can use channel to send a message lazily" do
    {:ok, ch} = Channel.start_link()

    :ok = Channel.subscribe(ch, self(), :foo)

    spawn(fn() -> Channel.send_lazy(ch, fn -> 42 end) end)

    assert_receive({:foo, 42})
  end

  test "lazy send doesn't evaluate function when no subscribers" do
    {:ok, ch} = Channel.start_link()

    target = self()
    f = fn ->
      send(target, :evaluated)
      42
    end

    spawn(fn() -> Channel.send_lazy(ch, f) end)

    :timer.sleep(50)

    refute_received(_)
  end

  test "can unsubscribe from channel" do
    {:ok, ch} = Channel.start_link()

    :ok = Channel.subscribe(ch, self(), :foo)

    Channel.unsubscribe(ch, self())

    :timer.sleep(100)

    spawn(fn() -> Channel.send(ch, 42) end)

    refute_receive({:foo, 42})
  end

  test "can unsubscribe from channel by token" do
    {:ok, ch} = Channel.start_link()

    :ok = Channel.subscribe(ch, self(), :foo)
    :ok = Channel.subscribe(ch, self(), :bar)

    Channel.unsubscribe(ch, self(), :foo)

    :timer.sleep(100)

    spawn(fn() -> Channel.send(ch, 42) end)

    refute_receive({:foo, 42})
    assert_receive({:bar, 42})
  end

  test "can map function to channel payload" do
    {:ok, ch} = Channel.start_link()
    {:ok, mapch} = Channel.map(ch, fn(x) -> x + 1 end)

    :ok = Channel.subscribe(mapch, self(), :foo)

    spawn(fn() -> Channel.send(ch, 42) end)

    assert_receive({:foo, 42})
  end
end