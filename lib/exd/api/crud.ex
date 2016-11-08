defmodule Exd.Api.Crud do
  @moduledoc """
  Generic implementation of get/post/update/delete for APIs. Note, that `Exd.Api` automaticly
  import `Exd.Api.Crud` in a scope, that you can define crud directly.

  ## Example of definition

      import Exd.Model
      model Example do
        field :test1
        field :test2
      end
      defmodule Example.Api do
        @moduledoc "Example module documentation"
        @name "Example"
        @tech_name "example"
        use Exd.Model.Api
        crud
      end

  ## Crud apis

  For more selective api definition, it is possible to add option `:only`.

      defmodule Example.Api do
        @moduledoc "Example module documentation"
        @name "Example"
        @tech_name "example"
        use Exd.Model.Api
        crud, only: [:post, :get]
      end
  """
  #import Ecdo
  alias Exd.Api.Callbacks

  defmacrop repo(api) do
    quote do: unquote(api).__exd_api__(:repo)
  end
  defmacrop model(api) do
    quote do: unquote(api).__exd_api__(:model)
  end
  defmacrop save(expression) do
    quote do
      try do unquote(expression) rescue error -> error end
    end
  end
  defmacrop unless_error(data, api, what_to_do) do
    quote do
      unless error = check_error(unquote(data), unquote(api)) do
        unquote(what_to_do)
      else error end
    end
  end

  @doc """
  Generic get function. There are different possiblities to get results. It possible to get results
  directly on `id`, on `name` (if defined in model). Or, due to query clauses.

  ## Examples

      iex> Exd.Api.Crud.get(api, %{"id" => 1})
      iex> Exd.Api.Crud.get(api, %{"name" => "test"})
      iex> Exd.Api.Crud.get(api, %{"where" => "id < 5", "limit" => "5"})
      iex> Exd.Api.Crud.get(api, %{"join" => ["x"], "order_by" => "x.name:asc"})

  ## Results

  Results to a list of found objects, and a list of links, attached to assoicated objects.

  """
  def get(api, params) do
    IO.puts "crud get"
    keys = Map.keys(params)
    if ("id" in keys) or ("name" in keys) do
      get_one(api, params)
    else
      select(api, params)
    end 
    |> IO.inspect
    |> format_data(api, params, as: :get)
    |> IO.inspect
  end

  defp get_one(api, %{"id" => id} = params) do
    # FIXME: get back to form of [{:==, :id, id}]
    # Once it doesn't generate it to a query with literals ids.
    # Problem is, that if we doesn't replace it with parameters (as we do it in id == "xyz")
    # the resulting query is "WHERE (a0.`id` = 1)" instead of WHERE (a0.`id` = ?)"
    # it results in much entries in prepared statements cache and in performance degradation.
    params = put_in(params["where"], ~s(id == "#{id}"))
    data = model(api) |> Ecdo.query(params) |> repo(api).one |> save
    unless_error(data, api, data)
  end
  defp get_one(api, %{"name" => name} = params) do
    params = put_in(params["where"], ~s(name == "#{name}"))
    data = model(api) |> Ecdo.query(params) |> repo(api).one |> save
    unless_error(data, api, data)
  end

  defp select(api, params), do:
    model(api) |> Ecdo.query(params |> search(api)) |> repo(api).all |> save

  defp search(%{"search" => search} = params, api) do
    searchable_fields = api.__exd_api__(:search)
                        |> Enum.map(fn(filed) -> {:like, Atom.to_string(filed), search} end)
                        |> build_or({})
    put_in(params["where"], (Map.get(params, "where", []) |> List.wrap) ++ searchable_fields)
  end
  defp search(params, _), do: params

  defp build_or([], acc), do: [acc]
  defp build_or([left | rest], {}), do: build_or(rest, left)
  defp build_or([left | rest], {_, _, _} = acc), do: build_or(rest, {:or, left, acc})

  @doc """
  Generic post function, which uses default changset implementation or model defined `changeset/3`
  function for validation, before inserting.

  ## Example of changset
    def changset(model, :create, params) do
      # Changeset on create
    end

  ## Results

  Results to an error of an link to object, which can be directly used in get.

  ## Default validation

  If there is no `changeset/3` exported, the default implementation doing simple `Ecto.Changeset.cast/4`
  with requireing all attributes without (not required are: `id`, `udpated_at`, `created_at`), if the
  `@required` is not overwritten in your API.
  """
  def post(api, params) when is_list(params), do: post(api, :maps.from_list(params))
  def post(api, params) do
    changeset = changeset(api.__exd_api__(:instance), api, :create, params)
    if changeset.valid? do
      save(repo(api).insert!(changeset)) |> notify(api, :after_post) |> format_data(api, params, as: :write)
    else
      %{errors: :maps.from_list(changeset.errors)}
    end
  end

  @doc """
  Generic put function, which uses default changset implementation or model defined `changeset/3`
  function for validation, before updating.

  ## Example of changset
    def changset(model, :update, params) do
      # Changeset on update
    end

  Results to an error of an link to object, which can be directly used in get.

  ## Default validation

  If there is no `changeset/3` exported, the default implementation doing simple `Ecto.Changeset.cast/4`
  with requireing all attributes without (not required are: `id`, `udpated_at`, `created_at`), if the
  `@required` is not overwritten in your API.
  """
  def put(api, params) when is_list(params), do: put(api, :maps.from_list(params))
  def put(api, params) do
    if data = get_one(api, params) do
      unless_error(data, api, put(data, api, params))
    end
  end

  @doc """
  Generic update on readed data.
  """
  def put(data, api, params) do
    changeset = changeset(data, api, :update, params)
    unmodified = params["if_unmodified_since"]
    changeset = if unmodified && Ecto.DateTime.to_iso8601(data.updated_at) != unmodified do
      Ecto.Changeset.add_error(changeset, :modified, "was modified since #{unmodified}")
    else changeset end

    if changeset.valid? do
      save(repo(api).update!(changeset)) |> notify(api, :after_put) |> format_data(api, params, as: :write)
    else
      %{errors: :maps.from_list(changeset.errors)}
    end
  end

  defp changeset(data, api, action, params) do
    if function_exported?(model(api), :changeset, 3) do
      api.model.changeset(data, action, params)
    else
      {required, optional} = if action == :create do
        {api.__exd_api__(:required), api.__exd_api__(:optional)}
      else
        {~W(), api.__exd_api__(:changable)}
      end
      Ecto.Changeset.cast(data, params, required, optional)
    end
  end

  @doc """
  Generic delete function, which deletes data on id or on name, if exists.
  """
  def delete(api, params) do
    case get_one(api, params) do
      nil    -> nil
      result -> unless_error(result, api, save(repo(api).delete!(result)) |> notify(api, :after_delete) |> format_data(api, params, as: :write))
    end
  end

  defp check_error(%Ecto.ConstraintError{constraint: constraint, type: type} = error, api) do
    case type do
      :unique ->
        check_unique_error(error, api)
      :foreign_key ->
        check_foreign_key_error(error, api)
    end
  end
  defp check_error(%{message: "tcp connect: econnrefused"}, _api) do
    %{errors: %{database: "not available"}}
  end
  defp check_error(%{errors: _} = error, _), do: error
  defp check_error(_, _), do: nil

  defp check_unique_error(%Ecto.ConstraintError{constraint: constraint}, api) do
    source = api.__schema__(:source)
    {0, l} = :binary.match(constraint, [source])
    field = String.slice(constraint, l + 1, byte_size(constraint) - l - unquote(byte_size("__index"))) |> String.to_atom()
    %{errors: Map.put(%{}, field, "exists")}
  end

  defp check_foreign_key_error(%Ecto.ConstraintError{constraint: constraint}, api) do
    source = api.__schema__(:source)
    {0, l} = :binary.match(constraint, [source])
    relation = String.slice(constraint, l + 1, byte_size(constraint) - l - unquote(byte_size("__fkey"))) |> String.to_atom()
    %{errors: Map.put(%{}, relation, "not found")}
  end

  defp notify(data, api, callback) do
    unless_error(data, api, Callbacks.__apply__(api, callback, data))
  end

  defp format_data(data, api, params, opts) do
    # 'select' response is not __struct__, so we need to  format in other place
    case params["select"] do
      nil -> unless_error(data, api, export_data(data, opts))
      _ -> unless_error(data, api, data)
    end
  end

  def export_data(nil, _opts), do: nil
  def export_data(data, opts \\ [as: :get])
  def export_data(data, opts) when is_list(data), do: Enum.map(data, &export_data(&1, opts))
  def export_data(data, opts) do
    case opts[:as] do
      :get ->
        Map.drop(data, [:__meta__, :__struct__]) |> Enum.filter_map(&filter_assocs/1, &transform/1) |> Enum.into(%{})
      :write ->
        %{id: data.id}
    end
  end

  defp filter_assocs({_key, %Ecto.Association.NotLoaded{}}), do: false
  defp filter_assocs({_key, _}), do: true

  # TODO: remove hack
  defp transform({key, %{__struct__: Ecto.DateTime} = struct}), do: {key, Ecto.DateTime.to_iso8601(struct)}
  defp transform({key, list}) when is_list(list), do: {key, Enum.map(list, &export_data/1)}
  defp transform({key, %{__meta__: _} = data}), do: {key, export_data(data)}
  defp transform({key, value}), do: {key, value}

  @default_crud [:get, :post, :put, :delete]
  defmacro crud(opts \\ []) do
    actions = opts[:only] || @default_crud
    quote bind_quoted: [actions: actions] do
      if :post in actions do
        api "post", :__post__
        @doc """
        Method: `post`.
        Inserts #{String.downcase(@name)} object.

        ## Parameters

        #{ Exd.Api.Crud.description(@model, @exported, @read_only, @required, :post) }
        """
        def __post__(args), do:
          Exd.Metrics.request(__MODULE__, :post, fn -> Exd.Api.Crud.post(__MODULE__, args) end)
      end

      if :put in actions do
        api "put", :__put__
        @doc """
        Method: `put`.
        Update #{String.downcase(@name)} object.

        ## Parameters

        #{ Exd.Api.Crud.description(@model, @exported, @read_only, @required, :put) }
        """
        def __put__(args), do:
          Exd.Metrics.request(__MODULE__, :put, fn -> Exd.Api.Crud.put(__MODULE__, args) end)
      end

      if :get in actions do
        api "get", :__get__
        @doc """
        Method: `get`.
        Get #{String.downcase(@name)} object.

        ## Parameters

        #{ Exd.Api.Crud.description(@model, @exported, @read_only, @required, :get) }
        """
        def __get__(args), do:
          Exd.Metrics.request(__MODULE__, :get, fn -> Exd.Api.Crud.get(__MODULE__, args) end)
      end

      if :delete in actions do
        api "delete", :__delete__
        @doc """
        Method: `delete`.
        Delete #{String.downcase(@name)} object.

        ## Parameters

        #{ Exd.Api.Crud.description(@model, @exported, @read_only, @required, :delete) }
        """
        def __delete__(args), do:
          Exd.Metrics.request(__MODULE__, :delete, fn -> Exd.Api.Crud.delete(__MODULE__, args) end)
      end
    end
  end

  @doc """
  Generates description of method, based on model, exported, read_only and required fields and action.
  """
  def description(model, exported, read_only, required, action) when action in [:put, :post] do
    changable = exported -- read_only
    optional = if action == :post do changable -- required else changable end
    description = Enum.map(changable, fn(field) ->
      field_string(model, field, field in optional)
    end) |> Enum.join("\n")
    description <> update_attrs(action)
  end

  def description(model, exported, _read_only, _required, action) when action in [:get, :delete] do
    id_string   = if :id in exported do field_string(model, :id, false) <> "\n"     else "" end
    name_string = if :name in exported do field_string(model, :name, false) <> "\n" else "" end
    query_string = if action == :get do
    """
 * `where` - string, optional, identifies conditions on which it should be queried
 * `limit` - integer, optional, limit results of query
 * `load` - list of string, optional, identifies associations, which should be loaded
 * `offset` - integer, optional, offsets the number results
 * `order_by` - object, optional, set order of resulting query
 * `aggregate` - string, optional, aggregate information, available: `count`
    """
    else "" end
    id_string <> name_string <> query_string
  end

  defp field_string(model, field, optional) do
    optional_string = if optional do ", optional" else "" end
    type = model.__schema__(:type, field)
    " * `#{field}` - #{type}#{optional_string} #{model.__attribute_option__(field)[:desc] || ""}"
  end

  defp update_attrs(:post), do: ""
  defp update_attrs(:put) do
"""
 * `if_unmodified_since` - string, optional, should be sent a value of `updated_at`, which can be readed on get.
"""
  end
end
