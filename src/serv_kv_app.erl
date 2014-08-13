-module(serv_kv_app).
-include_lib("rafter/include/rafter_opts.hrl").
-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    start_app_deps(serv_kv),
    %% rafter
    Backend = app_helper:get_env(serv_kv, storage_backend, serv_kv_backend_eleveldb),
    LogDir = app_helper:get_env(serv_kv, rafter_root, "rafter"),
    filelib:ensure_dir(LogDir),
    Opts = #rafter_opts{state_machine=Backend, logdir=LogDir},
    rafter_consensus_sup:start_link({serv_kv_rafter, erlang:node()}, Opts).

stop(_State) ->
    ok.

%% @spec start_app_deps(App :: atom()) -> ok
%% @doc Start depedent applications of App.
start_app_deps(App) ->
    {ok, DepApps} = application:get_key(App, applications),
    _ = [ensure_started(A) || A <- DepApps],
    ok.


%% @spec ensure_started(Application :: atom()) -> ok
%% @doc Start the named application if not already started.
ensure_started(App) ->
    case application:start(App) of
	ok ->
	    ok;
	{error, {already_started, App}} ->
	    ok
    end.
