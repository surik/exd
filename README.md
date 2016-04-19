Exd [![Build Status](https://travis-ci.org/xerions/exd.svg)](https://travis-ci.org/xerions/exd) [![Coverage Status](https://coveralls.io/repos/xerions/exd/badge.svg?branch=master&service=github)](https://coveralls.io/github/xerions/exd?branch=master)
===

Main goals

* handling data patterns in consistent way
* consistent way to expose the models to CLI/API/WEB
* integration with erlang

Exd - library based on [ecto](https://github.com/elixir-lang/ecto) for productive boost in data handling for backend systems. There are some different goals, make it possible to quick bootstrap and [migrate](https://github.com/xerions/ecto_migrate), allow configuration-based change of models ( customizing ) and implementing API in generic way.

If some of functionality ( like [auto migration](https://github.com/xerions/ecto_migrate) ) will be usefull generally in ecto, we are ready to move and contribute it to ecto.

For playing with database and try all examples, use [ecto_it](https://github.com/xerions/ecto_it).

Development state
-----------------

Very alpha, functional, some parts are still not working or not working properly.

Configurable model on start
---------------------------

There is model_add construct and a function, which allows on start to define the model and with 'plugins', how should the data see.

```elixir
import Exd.Model

model Weather do # is for later at now
  schema "weather" do
    field :city
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :prcp,    :float, default: 0.0
  end

  def test1, do: 1
end # compiles to Ecto model

model_add WindWeather, to: Weather do
  schema do
    field :wind, :float, default: 0.0
  end
  def test2, do: 2
end
```

After that it possible to generate the right model on start:

```elixir
Exd.Model.compile(Weather, [WindWeather])
Exd.Model.compile(Weather, [])
```

This functionality may be changed in the future to an explicit composable model.

Export an API
-------------

It is possible to export your model in generic way to a consumer.

For example:

```elixir
defmodule Weather.Api do
  @moduledoc "Weather API documentation"
  @name "Weather"
  @tech_name "weather"
  use Exd.Api, model: Weather, repo: EctoIt.Repo
  crud
end
```

Use precompiled API. (Note: to get example work, you need to compile model and API, because for a iex compilation, the documentation is not available)
```
MIX_ENV=test iex -S mix
```

Now you have many different methods, which is possible to introspect with [apix](https://github.com/liveforeverx/apix).

```elixir
iex> Apix.spec(Weather.Api, :methods)
["options", "post", "put", "get", "delete"]
```

By using of `Exd.Api` you will be automatically get method options, which is possible to use to introspect yourself.

```elixir
iex> Apix.apply(Weather.Api, "options", %{})
```

You can describe nested API via `apis` option in Exd.Api. If you want to use CLI or WEB you should have application's API. This is achieved by adding attribute `@app: true` to API module.

For example:

```elixir
defmodule Example.Api do
  @moduledoc "Example application"
  @name "Example"
  @tech_name "exd"
  @app true
  use Exd.Api, apis: [City.Api, Weather.Api]
end
```

CLI
---

Now, you can generate CLI with:

```
mix exd.escript
```

Start named node:

```elixir
$ MIX_ENV=test iex --sname test -S mix
iex> Application.ensure_all_started(:ecto_it)
iex> Ecto.Migration.Auto.migrate(EctoIt.Repo, City)
iex> Ecto.Migration.Auto.migrate(EctoIt.Repo, Weather)
iex> :code.load_file(City.Api)
iex> :code.load_file(Weather.Api)
```

Now you can use CLI for accessing running node as:

```elixir
./exd insert exd/weather city:Berlin temp_hi:32 temp_lo:20
./exd get exd/weather id:1
```

For more information, see './exd -h'.
It is still work in progress, zmtp is not functional, as native formatter is not completly implemented, at the moment.

Data handling patterns
----------------------

There are some patterns on handling data (like inheritance, for example comment can inherit a user picture for that case, if the user changes the own picture, this specific comment will show old picture), that need to have generic handlers. [WiP]

Expose ecto to erlang application
---------------------------------

As the ecto interface is based heavily on macros, and not directly invokable in erlang, there should exists reach erlang API to allow to handle and manipulate Ecto model from erlang application. [WiP]

Metrics
-------

EXD collects some metrics via exometer_core. If you want to report those metrics you have to initialize metrics to each API:

    Exd.Metrics.init_metrics(City.Api)

It will collect the following metrics:

    * request counter
    * request handle times
    * object counter

The request metrics are broken down by the method which was used (put, post, delete, update)
and by the status of the request (success, error, db_not_available). Further a request counter
and handle time metric is initialized at start for all API calls combined.

The handle times metrics are internally generated using histograms. These histograms have a time span of 60s.

The exometer IDs can be viewed in the Exd.Metrics module or just execute `:exometer_report.list_metrics([:exd])`
_after_ you initialized your API metrics.


Model-driven development
------------------------

For different APIs, there should be an adaptor, which allows to define the model API in consistent way. There are 2 examples at the moment:

* json-rpc - all data manipulation should be consistent with different models and the code should be written only once. ( `Exd.Plugin.Hello` - build-in example).
* CLI - see `CLI` section

Tests
-----

To run tests, you need to pass environment which depends on the database. For example:

```
MIX_ENV=pg mix test
```

or

```
MIX_ENV=mysql mix test
```
