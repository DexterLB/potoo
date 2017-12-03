defmodule JsonTest do
  use ExUnit.Case
  doctest Mesh.ServerUtils.Json

  import Mesh.ServerUtils.Json
  alias Mesh.ServerUtils.PidCache

  setup do
    {:ok, pc} = PidCache.start_link()

    [pc: pc]
  end

  test "can jsonify bare values", %{pc: pc} do
    assert jsonify(42, pc)      == 42
    assert jsonify(42.5, pc)    == 42.5
    assert jsonify(nil, pc)     == nil
    assert jsonify("foo", pc)   == "foo"
    assert jsonify(true, pc)    == true
  end

  test "can jsonify map with string keys", %{pc: pc} do
    assert jsonify(%{"foo" => 42, "bar" => true}, pc) == %{"foo" => 42, "bar" => true}
  end

  test "can jsonify map with atom keys to map of string keys", %{pc: pc} do
    assert jsonify(%{foo: 42, bar: true}, pc) == %{"foo" => 42, "bar" => true}
  end

  test "can jsonify tuple to list", %{pc: pc} do
    assert jsonify({:foo, "bar"}, pc) == ["foo", "bar"]
  end

  test "can jsonify function", %{pc: pc} do
    fun = %Mesh.Contract.Function{
      name: "add",
      argument: {:struct, %{"b" => :integer, "a" => :integer}},
      retval: :integer,
      data: %{"description" => "adds two integers"}
    }

    assert jsonify(fun, pc) == %{
      "__type__" => "function",
      "name" => "add",
      "argument" => ["struct", %{"b" => "integer", "a" => "integer"}],
      "retval" => "integer",
      "data" => %{"description" => "adds two integers"}
    }
  end

  test "can jsonify delegate", %{pc: pc} do
    del = %Mesh.Contract.Delegate{
      destination: self(),
      data: %{"foo" => "bar"}
    }

    assert jsonify(del, pc) == %{
      "__type__" => "delegate",
      "destination" => PidCache.get(pc, {:delegate, self()}),
      "data" => %{"foo" => "bar"}
    }
  end

  test "can jsonify channel", %{pc: pc} do
    {:ok, chan} = Mesh.Channel.start_link()
    {Mesh.Channel, chan_pid} = chan

    assert jsonify(chan, pc) == %{
      "__type__" => "channel",
      "id" => PidCache.get(pc, {:channel, chan_pid})
    }
  end
end