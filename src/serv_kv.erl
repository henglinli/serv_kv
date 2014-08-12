%%%-------------------------------------------------------------------
%%% @author HenryLee <lee@OSX.local>
%%% @copyright (C) 2014, HenryLee
%%% @doc
%%%
%%% @end
%%% Created : 10 Aug 2014 by HenryLee <lee@OSX.local>
%%%-------------------------------------------------------------------
-module(serv_kv).

%% API
-export([get/1, put/2, delete/1]).
-export([set_config/1]).
-export([ping/0]).
%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
%% @doc Pings a random vnode to make sure communication is functional
ping() ->
    DocIdx = riak_core_util:chash_key({<<"ping">>, term_to_binary(now())}),
    PrefList = riak_core_apl:get_primary_apl(DocIdx, 1, serv_kv),
    [{IndexNode, _Type}] = PrefList,
    riak_core_vnode_master:sync_spawn_command(IndexNode, ping, serv_kv_vnode_master).
-spec set_config(Nodes :: [atom()]) ->
    Result :: term().
set_config(Nodes) ->
    Peers = [{serv_kv_rafter, Node} || Node <- Nodes],
    Vstruct = rafter_voting_majority:majority(Peers),
    rafter:set_config(serv_kv_rafter, Vstruct).

-spec get( Key::binary()) ->
		 {ok, Value::binary()} |
		 {error, Reason::term()}.
get(Key) ->
    rafter:read_op(serv_kv_rafter, {get, Key}).

-spec put(Key::binary(), Value::binary()) ->
		 ok | {error, Reason::term()}.
put(Key, Value) ->
    rafter:op(serv_kv_rafter, {put, Key, Value}).

-spec delete(Key::binary()) ->
		    ok | {error, Reason::term()}.
delete(Key) ->
    rafter:op(serv_kv_rafter, {delete, Key}).


%%%===================================================================
%%% Internal functions
%%%===================================================================
