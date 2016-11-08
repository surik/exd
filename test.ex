Application.ensure_all_started(:ecto_it)
Ecto.Migration.Auto.migrate(EctoIt.Repo, City)
Ecto.Migration.Auto.migrate(EctoIt.Repo, Weather)
:code.load_file(City.Api)
:code.load_file(Weather.Api)
Application.ensure_all_started :hello
:exometer_report.add_reporter(:exometer_report_tty, [])
uri = "http://127.0.0.1:8080"
:hello.start_listener(uri, [], :hello_proto_jsonrpc, [], :hello_router)
for api <- [City.Api, Weather.Api] do
  :hello.start_service(api, [])
  :hello.bind(uri, api)
  Exd.Metrics.subscribe(api)
end

:io.format("~p~n", [:exometer_report.list_subscriptions :exometer_report_tty])
