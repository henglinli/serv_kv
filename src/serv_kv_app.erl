-module(serv_kv_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    riak_core_util:start_app_deps(serv_kv),
    case serv_kv_sup:start_link() of
	{ok, Pid} ->
	    %% ok = riak_core:register(serv_kv, [
	    %% 				      %%{vnode_module, riak_kv_vnode},
	    %% 				      {stat_mod, riak_kv_stat}
	    %% 				     ]),
	    {ok, Pid};
	Else ->
	    Else
    end.

stop(_State) ->
    ok.
