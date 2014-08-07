%% -------------------------------------------------------------------
%%
%% riak_client: object used for access into the riak system
%%
%% Copyright (c) 2007-2013 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% @doc object used for access into the riak system

-module(serv_kv).

-export([start/1]).
-export([local_client/0]).
-export([new/2]).
-export([get/3,get/4,get/5]).
-export([put/2,put/3,put/4,put/5,put/6]).
-export([delete/3,delete/4,delete/5]).
-export([delete_vclock/4,delete_vclock/5,delete_vclock/6]).
-export([set_bucket/3,get_bucket/2,reset_bucket/2]).
-export([reload_all/2]).
-export([remove_from_cluster/2]).
-export([get_stats/2]).
-export([get_client_id/1]).
-export([ensemble/1]).

-compile({no_auto_import,[put/2]}).
%% @type default_timeout() = 60000
-define(DEFAULT_TIMEOUT, 60000).
-define(DEFAULT_ERRTOL, 0.00003).

%% TODO: This type needs to be better specified and validated against
%%       any dependents on riak_kv.
%%
%%       We want this term to be opaque, but can't because Dialyzer
%%       doesn't like the way it's specified.
%%
%%       opaque type riak_client() is underspecified and therefore meaningless
-type riak_client() :: term().

-export_type([riak_client/0]).

start(BucketType) ->
    riak_core_bucket_type:create(BucketType, [{consistent, true}]),
    riak_core_bucket_type:activate(BucketType),
    case riak_ensemble_manager:enabled() of
	false ->
	    riak_ensemble_manager:enable();
	true ->
	    ok
    end.

%% @spec new(Node, ClientId) -> riak_client().
%% @doc Return a riak client instance.
local_client() ->
    Node = erlang:node(),
    new(Node, riak_core_util:mkclientid(Node)).

new(Node, ClientId) ->
    {?MODULE, [Node,ClientId]}.

%% @spec get(riak_object:bucket(), riak_object:key(), riak_client()) ->
%%       {ok, riak_object:riak_object()} |
%%       {error, notfound} |
%%       {error, timeout} |
%%       {error, {n_val_violation, N::integer()}} |
%%       {error, {r_val_unsatisfied, R::integer(), Replies::integer()}} |
%%       {error, Err :: term()}
%% @doc Fetch the object at Bucket/Key.  Return a value as soon as the default
%%      R-value for the nodes have responded with a value or error.
%% @equiv get(Bucket, Key, R, default_timeout())
get(Bucket, Key, {?MODULE, [_Node, _ClientId]}=THIS) ->
    get(Bucket, Key, [], THIS).

consistent_get(Bucket, Key, Options, {?MODULE, [Node, _ClientId]}) ->
    BKey = {Bucket, Key},
    Ensemble = ensemble(BKey),
    lager:info("ensemble ~p", [Ensemble]),
    Timeout = recv_timeout(Options),
    StartTS = os:timestamp(),
    Result = case riak_ensemble_client:kget(Node, Ensemble, BKey, Timeout) of
		 {error, _}=Err ->
		     Err;
		 {ok, Obj} ->
		     case riak_object:get_value(Obj) of
			 notfound ->
			     {error, notfound};
			 _ ->
			     {ok, Obj}
		     end
	     end,
    maybe_update_consistent_stat(Node, consistent_get, Bucket, StartTS, Result),
    Result.

maybe_update_consistent_stat(_Node, consistent_get, _Bucket, _StartTS, _Result) ->
    ok;
maybe_update_consistent_stat(_Node, consistent_put, _Bucket, _StartTS, _Result) ->
    ok;

maybe_update_consistent_stat(Node, Stat, Bucket, StartTS, Result) ->
    case node() of
	Node ->
	    Duration = timer:now_diff(os:timestamp(), StartTS),
	    ObjFmt = riak_core_capability:get({riak_kv, object_format}, v0),
	    ObjSize = case Result of
			  {ok, Obj} ->
			      riak_object:approximate_size(ObjFmt, Obj);
			  _ ->
			      undefined
		      end,
	    riak_kv_stat:update({Stat, Bucket, Duration, ObjSize}),
	    ok;
	_ ->
	    ok
    end.

%% @spec get(riak_object:bucket(), riak_object:key(), options(), riak_client()) ->
%%       {ok, riak_object:riak_object()} |
%%       {error, notfound} |
%%       {error, {deleted, vclock()}} |
%%       {error, timeout} |
%%       {error, {n_val_violation, N::integer()}} |
%%       {error, {r_val_unsatisfied, R::integer(), Replies::integer()}} |
%%       {error, Err :: term()}
%% @doc Fetch the object at Bucket/Key.  Return a value as soon as R-value for the nodes
%%      have responded with a value or error.
get(Bucket, Key, Options, {?MODULE, [Node, _ClientId]}=THIS) when is_list(Options) ->
    case consistent_object(Node, Bucket) of
	true ->
	    consistent_get(Bucket, Key, Options, THIS);
	false ->
	    {error, not_conistent};
	{error,_}=Err ->
	    Err
    end;

%% @spec get(riak_object:bucket(), riak_object:key(), R :: integer(), riak_client()) ->
%%       {ok, riak_object:riak_object()} |
%%       {error, notfound} |
%%       {error, timeout} |
%%       {error, {n_val_violation, N::integer()}} |
%%       {error, {r_val_unsatisfied, R::integer(), Replies::integer()}} |
%%       {error, Err :: term()}
%% @doc Fetch the object at Bucket/Key.  Return a value as soon as R
%%      nodes have responded with a value or error.
%% @equiv get(Bucket, Key, R, default_timeout())
get(Bucket, Key, R, {?MODULE, [_Node, _ClientId]}=THIS) ->
    get(Bucket, Key, [{r, R}], THIS).

%% @spec get(riak_object:bucket(), riak_object:key(), R :: integer(),
%%           TimeoutMillisecs :: integer(), riak_client()) ->
%%       {ok, riak_object:riak_object()} |
%%       {error, notfound} |
%%       {error, timeout} |
%%       {error, {n_val_violation, N::integer()}} |
%%       {error, {r_val_unsatisfied, R::integer(), Replies::integer()}} |
%%       {error, Err :: term()}
%% @doc Fetch the object at Bucket/Key.  Return a value as soon as R
%%      nodes have responded with a value or error, or TimeoutMillisecs passes.
get(Bucket, Key, R, Timeout, {?MODULE, [_Node, _ClientId]}=THIS) when
				  (is_binary(Bucket) orelse is_tuple(Bucket)),
				  is_binary(Key),
				  (is_atom(R) or is_integer(R)),
				  is_integer(Timeout) ->
    get(Bucket, Key, [{r, R}, {timeout, Timeout}], THIS).


%% @spec put(RObj :: riak_object:riak_object(), riak_client()) ->
%%        ok |
%%       {error, too_many_fails} |
%%       {error, timeout} |
%%       {error, {n_val_violation, N::integer()}}
%% @doc Store RObj in the cluster.
%%      Return as soon as the default W value number of nodes for this bucket
%%      nodes have received the request.
%% @equiv put(RObj, [])
put(RObj, {?MODULE, [_Node, _ClientId]}=THIS) -> put(RObj, [], THIS).

consistent_put(RObj, Options, {?MODULE, [Node, _ClientId]}) ->
    Bucket = riak_object:bucket(RObj),
    BKey = {Bucket, riak_object:key(RObj)},
    Ensemble = ensemble(BKey),
    NewObj = riak_object:apply_updates(RObj),
    Timeout = recv_timeout(Options),
    StartTS = os:timestamp(),
    Result = case consistent_put_type(RObj, Options) of
		 update ->
		     riak_ensemble_client:kupdate(Node, Ensemble, BKey, RObj, NewObj, Timeout);
		 put_once ->
		     riak_ensemble_client:kput_once(Node, Ensemble, BKey, NewObj, Timeout)
		%% TODO: Expose client option to explicitly request overwrite
		 %overwrite ->
		     %riak_ensemble_client:kover(Node, Ensemble, BKey, NewObj, Timeout)
	     end,
    maybe_update_consistent_stat(Node, consistent_put, Bucket, StartTS, Result),
    ReturnBody = lists:member(returnbody, Options),
    case Result of
	{error, _}=Error ->
	    Error;
	{ok, Obj} when ReturnBody ->
	    {ok, Obj};
	{ok, _Obj} ->
	    ok
    end.

consistent_put_type(RObj, Options) ->
    VClockGiven = (riak_object:vclock(RObj) =/= []),
    IfMissing = lists:member({if_none_match, true}, Options),
    if VClockGiven ->
	    update;
       IfMissing ->
	    put_once;
       true ->
	    %% Defaulting to put_once here for safety.
	    %% Our client API makes it too easy to accidently send requests
	    %% without a provided vector clock and clobber your data.
	    %% overwrite
	    %% TODO: Expose client option to explicitly request overwrite
	    put_once
    end.

%% @spec put(RObj :: riak_object:riak_object(), riak_kv_put_fsm::options(), riak_client()) ->
%%       ok |
%%       {ok, details()} |
%%       {ok, riak_object:riak_object()} |
%%       {ok, riak_object:riak_object(), details()} |
%%       {error, notfound} |
%%       {error, timeout} |
%%       {error, {n_val_violation, N::integer()}} |
%%       {error, Err :: term()}
%%       {error, Err :: term(), details()}
%% @doc Store RObj in the cluster.
put(RObj, Options, {?MODULE, [Node, _ClientId]}=THIS) when is_list(Options) ->
    case consistent_object(Node, riak_object:bucket(RObj)) of
	true ->
	    consistent_put(RObj, Options, THIS);
	false ->
	    {error, not_conistent};
	{error,_}=Err ->
	    Err
    end;

%% @spec put(RObj :: riak_object:riak_object(), W :: integer(), riak_client()) ->
%%        ok |
%%       {error, too_many_fails} |
%%       {error, timeout} |
%%       {error, {n_val_violation, N::integer()}}
%% @doc Store RObj in the cluster.
%%      Return as soon as at least W nodes have received the request.
%% @equiv put(RObj, [{w, W}, {dw, W}])
put(RObj, W, {?MODULE, [_Node, _ClientId]}=THIS) -> put(RObj, [{w, W}, {dw, W}], THIS).

%% @spec put(RObj::riak_object:riak_object(),W :: integer(),RW :: integer(), riak_client()) ->
%%        ok |
%%       {error, too_many_fails} |
%%       {error, timeout} |
%%       {error, {n_val_violation, N::integer()}}
%% @doc Store RObj in the cluster.
%%      Return as soon as at least W nodes have received the request, and
%%      at least DW nodes have stored it in their storage backend.
%% @equiv put(Robj, W, DW, default_timeout())
put(RObj, W, DW, {?MODULE, [_Node, _ClientId]}=THIS) -> put(RObj, [{w, W}, {dw, DW}], THIS).

%% @spec put(RObj::riak_object:riak_object(), W :: integer(), RW :: integer(),
%%           TimeoutMillisecs :: integer(), riak_client()) ->
%%        ok |
%%       {error, too_many_fails} |
%%       {error, timeout} |
%%       {error, {n_val_violation, N::integer()}}
%% @doc Store RObj in the cluster.
%%      Return as soon as at least W nodes have received the request, and
%%      at least DW nodes have stored it in their storage backend, or
%%      TimeoutMillisecs passes.
put(RObj, W, DW, Timeout, {?MODULE, [_Node, _ClientId]}=THIS) ->
    put(RObj,  [{w, W}, {dw, DW}, {timeout, Timeout}], THIS).

%% @spec put(RObj::riak_object:riak_object(), W :: integer(), RW :: integer(),
%%           TimeoutMillisecs :: integer(), Options::list(), riak_client()) ->
%%        ok |
%%       {error, too_many_fails} |
%%       {error, timeout} |
%%       {error, {n_val_violation, N::integer()}}
%% @doc Store RObj in the cluster.
%%      Return as soon as at least W nodes have received the request, and
%%      at least DW nodes have stored it in their storage backend, or
%%      TimeoutMillisecs passes.
put(RObj, W, DW, Timeout, Options, {?MODULE, [_Node, _ClientId]}=THIS) ->
    put(RObj, [{w, W}, {dw, DW}, {timeout, Timeout} | Options], THIS).

%% @spec delete(riak_object:bucket(), riak_object:key(), riak_client()) ->
%%        ok |
%%       {error, too_many_fails} |
%%       {error, notfound} |
%%       {error, timeout} |
%%       {error, Err :: term()}
%% @doc Delete the object at Bucket/Key.  Return a value as soon as RW
%%      nodes have responded with a value or error.
%% @equiv delete(Bucket, Key, RW, default_timeout())
delete(Bucket,Key,{?MODULE, [_Node, _ClientId]}=THIS) -> delete(Bucket,Key,[],?DEFAULT_TIMEOUT,THIS).

%% @spec delete(riak_object:bucket(), riak_object:key(), RW :: integer(), riak_client()) ->
%%        ok |
%%       {error, too_many_fails} |
%%       {error, notfound} |
%%       {error, timeout} |
%%       {error, Err :: term()}
%% @doc Delete the object at Bucket/Key.  Return a value as soon as W/DW (or RW)
%%      nodes have responded with a value or error.
%% @equiv delete(Bucket, Key, RW, default_timeout())
delete(Bucket,Key,Options,{?MODULE, [_Node, _ClientId]}=THIS) when is_list(Options) ->
    delete(Bucket,Key,Options,?DEFAULT_TIMEOUT,THIS);
delete(Bucket,Key,RW,{?MODULE, [_Node, _ClientId]}=THIS) ->
    delete(Bucket,Key,[{rw, RW}],?DEFAULT_TIMEOUT,THIS).

%% @spec delete(riak_object:bucket(), riak_object:key(), RW :: integer(),
%%           TimeoutMillisecs :: integer(), riak_client()) ->
%%        ok |
%%       {error, too_many_fails} |
%%       {error, notfound} |
%%       {error, timeout} |
%%       {error, {n_val_violation, N::integer()}} |
%%       {error, Err :: term()}
%% @doc Delete the object at Bucket/Key.  Return a value as soon as W/DW (or RW)
%%      nodes have responded with a value or error, or TimeoutMillisecs passes.
delete(Bucket,Key,Options,Timeout,{?MODULE, [Node, _ClientId]}=THIS) when is_list(Options) ->
    case consistent_object(Node, Bucket) of
	true ->
	    consistent_delete(Bucket, Key, Options, Timeout, THIS);
	false ->
	    {error, not_conistent};
	{error,_}=Err ->
	    Err
    end;
delete(Bucket,Key,RW,Timeout,{?MODULE, [_Node, _ClientId]}=THIS) ->
    delete(Bucket,Key,[{rw, RW}], Timeout, THIS).

consistent_delete(Bucket, Key, Options, _Timeout, {?MODULE, [Node, _ClientId]}) ->
    BKey = {Bucket, Key},
    Ensemble = ensemble(BKey),
    RTimeout = recv_timeout(Options),
    case riak_ensemble_client:kdelete(Node, Ensemble, BKey, RTimeout) of
	{error, _}=Err ->
	    Err;
	{ok, Obj} when element(1, Obj) =:= r_object ->
	    ok
    end.

%% @spec delete_vclock(riak_object:bucket(), riak_object:key(), vclock:vclock(), riak_client()) ->
%%        ok |
%%       {error, too_many_fails} |
%%       {error, notfound} |
%%       {error, timeout} |
%%       {error, Err :: term()}
%% @doc Delete the object at Bucket/Key.  Return a value as soon as W/DW (or RW)
%%      nodes have responded with a value or error.
%% @equiv delete(Bucket, Key, RW, default_timeout())
delete_vclock(Bucket,Key,VClock,{?MODULE, [_Node, _ClientId]}=THIS) ->
    delete_vclock(Bucket,Key,VClock,[{rw,default}],?DEFAULT_TIMEOUT,THIS).

%% @spec delete_vclock(riak_object:bucket(), riak_object:key(), vclock::vclock(),
%%                     RW :: integer(), riak_client()) ->
%%        ok |
%%       {error, too_many_fails} |
%%       {error, notfound} |
%%       {error, timeout} |
%%       {error, Err :: term()}
%% @doc Delete the object at Bucket/Key.  Return a value as soon as W/DW (or RW)
%%      nodes have responded with a value or error.
%% @equiv delete(Bucket, Key, RW, default_timeout())
delete_vclock(Bucket,Key,VClock,Options,{?MODULE, [_Node, _ClientId]}=THIS) when is_list(Options) ->
    delete_vclock(Bucket,Key,VClock,Options,?DEFAULT_TIMEOUT,THIS);
delete_vclock(Bucket,Key,VClock,RW,{?MODULE, [_Node, _ClientId]}=THIS) ->
    delete_vclock(Bucket,Key,VClock,[{rw, RW}],?DEFAULT_TIMEOUT,THIS).

%% @spec delete_vclock(riak_object:bucket(), riak_object:key(), vclock:vclock(), RW :: integer(),
%%           TimeoutMillisecs :: integer(), riak_client()) ->
%%        ok |
%%       {error, too_many_fails} |
%%       {error, notfound} |
%%       {error, timeout} |
%%       {error, {n_val_violation, N::integer()}} |
%%       {error, Err :: term()}
%% @doc Delete the object at Bucket/Key.  Return a value as soon as W/DW (or RW)
%%      nodes have responded with a value or error, or TimeoutMillisecs passes.
delete_vclock(Bucket,Key,VClock,Options,Timeout,{?MODULE, [Node, _ClientId]}=THIS) when is_list(Options) ->
    case consistent_object(Node, Bucket) of
	true ->
	    consistent_delete_vclock(Bucket, Key, VClock, Options, Timeout, THIS);
	false ->
	    {error, not_conistent};
	{error,_}=Err ->
	    Err
    end;
delete_vclock(Bucket,Key,VClock,RW,Timeout,{?MODULE, [_Node, _ClientId]}=THIS) ->
    delete_vclock(Bucket,Key,VClock,[{rw, RW}],Timeout,THIS).

consistent_delete_vclock(Bucket, Key, VClock, Options, _Timeout, {?MODULE, [Node, _ClientId]}) ->
    BKey = {Bucket, Key},
    Ensemble = ensemble(BKey),
    Current = riak_object:set_vclock(riak_object:new(Bucket, Key, <<>>),
				     VClock),
    RTimeout = recv_timeout(Options),
    case riak_ensemble_client:ksafe_delete(Node, Ensemble, BKey, Current, RTimeout) of
	{error, _}=Err ->
	    Err;
	{ok, Obj} when element(1, Obj) =:= r_object ->
	    ok
    end.

%% @spec set_bucket(riak_object:bucket(), [BucketProp :: {atom(),term()}], riak_client()) -> ok
%% @doc Set the given properties for Bucket.
%%      This is generally best if done at application start time,
%%      to ensure expected per-bucket behavior.
%% See riak_core_bucket for expected useful properties.
set_bucket(BucketName,BucketProps,{?MODULE, [Node, _ClientId]}) ->
    rpc:call(Node,riak_core_bucket,set_bucket,[BucketName,BucketProps]).
%% @spec get_bucket(riak_object:bucket(), riak_client()) -> [BucketProp :: {atom(),term()}]
%% @doc Get all properties for Bucket.
%% See riak_core_bucket for expected useful properties.
get_bucket(BucketName, {?MODULE, [Node, _ClientId]}) ->
    rpc:call(Node,riak_core_bucket,get_bucket,[BucketName]).
%% @spec reset_bucket(riak_object:bucket(), riak_client()) -> ok
%% @doc Reset properties for this Bucket to the default values
reset_bucket(BucketName, {?MODULE, [Node, _ClientId]}) ->
    rpc:call(Node,riak_core_bucket,reset_bucket,[BucketName]).
%% @spec reload_all(Module :: atom(), riak_client()) -> term()
%% @doc Force all Riak nodes to reload Module.
%%      This is used when loading new modules for map/reduce functionality.
reload_all(Module, {?MODULE, [Node, _ClientId]}) -> rpc:call(Node,riak_core_util,reload_all,[Module]).

%% @spec remove_from_cluster(ExitingNode :: atom(), riak_client()) -> term()
%% @doc Cause all partitions owned by ExitingNode to be taken over
%%      by other nodes.
remove_from_cluster(ExitingNode, {?MODULE, [Node, _ClientId]}) ->
    rpc:call(Node, riak_core_gossip, remove_from_cluster,[ExitingNode]).

get_stats(local, {?MODULE, [Node, _ClientId]}) ->
    [{Node, rpc:call(Node, riak_kv_stat, get_stats, [])}];
get_stats(global, {?MODULE, [Node, _ClientId]}) ->
    {ok, Ring} = rpc:call(Node, riak_core_ring_manager, get_my_ring, []),
    Nodes = riak_core_ring:all_members(Ring),
    [{N, rpc:call(N, riak_kv_stat, get_stats, [])} || N <- Nodes].

%% @doc Return the client id being used for this client
get_client_id({?MODULE, [_Node, ClientId]}) ->
    ClientId.

recv_timeout(Options) ->
    case proplists:get_value(recv_timeout, Options) of
	undefined ->
	    %% If no reply timeout given, use the FSM timeout + 100ms to give it a chance
	    %% to respond.
	    proplists:get_value(timeout, Options, ?DEFAULT_TIMEOUT) + 100;
	Timeout ->
	    %% Otherwise use the directly supplied timeout.
	    Timeout
    end.

ensemble(BKey={Bucket, _Key}) ->
    {ok, CHBin} = riak_core_ring_manager:get_chash_bin(),
    DocIdx = riak_core_util:chash_key(BKey),
    Partition = chashbin:responsible_index(DocIdx, CHBin),
    N = riak_core_bucket:n_val(riak_core_bucket:get_bucket(Bucket)),
    {kv, Partition, N}.

consistent_object(Node, Bucket) when Node =:= node() ->
    riak_kv_util:consistent_object(Bucket);
consistent_object(Node, Bucket) ->
    case rpc:call(Node, riak_kv_util, consistent_object, [Bucket]) of
	{badrpc, {'EXIT', {undef, _}}} ->
	    false;
	{badrpc, _}=Err ->
	    {error, Err};
	Result ->
	    Result
    end.
