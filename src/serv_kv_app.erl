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
	    ok = riak_core:register(serv_kv, [
	    				      {vnode_module, serv_kv_vnode}
	    				     ]),
	    ok = riak_core_node_watcher:service_up(serv_kv, erlang:self()),
	    ok = riak_core_ring_events:add_guarded_handler(serv_kv_event_handler_ring, []),
	    ok = riak_core_node_watcher_events:add_guarded_handler(serv_kv_event_handler_node, []),
	    {ok, Pid};
	Else ->
	    Else
    end.

stop(_State) ->
    ok.
