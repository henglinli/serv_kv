%%%-------------------------------------------------------------------
%%% @author HenryLee <lee@OSX.local>
%%% @copyright (C) 2014, HenryLee
%%% @doc
%%%
%%% @end
%%% Created : 10 Aug 2014 by HenryLee <lee@OSX.local>
%%%-------------------------------------------------------------------
-module(serv_kv_backend_eleveldb).

-behaviour(rafter_backend).

%% rafter_backend callbacks
-export([init/1, stop/1, read/2, write/2]).

%% API
-export([]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
-record(state, {peer :: atom() | {atom(), atom()}}).

init(Peer) ->
    #state{peer=Peer}.

stop(State) ->
    State.

read({get, Bucket, Key}, State) ->
    Val = {ok, {Bucket, Key}},
    {Val, State};

read(_, State) ->
    {{error, read_badarg}, State}.

write({put, Bucket, Key, Value}, State) ->
    Val = {ok, {Bucket, Key, Value}},
    {Val, State};

write({delete, Bucket, Key}, State) ->
    Val = {ok, {Bucket, Key}},
    {Val, State};

write(_, State) ->
    {{error, write_badarg}, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
