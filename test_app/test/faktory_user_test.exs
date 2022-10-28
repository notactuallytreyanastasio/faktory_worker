defmodule FaktoryUserTest do
  use ExUnit.Case
  doctest FaktoryUser

  test "greets the world" do
    assert FaktoryUser.hello() == :world
  end
end
