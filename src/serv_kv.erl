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
-export([get/3, put/4, delete/3]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
-spec get(Self::atom(), Bucket::binary(), Key::binary()) -> 
		 {ok, Value::binary()} |
		 {error, Reason::term()}.
get(Self, Bucket, Key) ->
    rafter:read_op(Self, {get, Bucket, Key}).

-spec put(Self::atom(), Bucket::binary(), Key::binary(), Value::binary()) -> 
		 ok | {error, Reason::term()}.
put(Self, Bucket, Key, Value) ->
    rafter:op(Self, {put, Bucket, Key, Value}).

-spec delete(Self::atom(), Bucket::binary(), Key::binary()) -> 		  
		    ok | {error, Reason::term()}.
delete(Self, Bucket, Key) ->
    rafter:op(Self, {delete, Bucket, Key}).


%%%===================================================================
%%% Internal functions
%%%===================================================================
