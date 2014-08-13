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
-record(state, {peer :: atom() | {atom(), atom()},
		db :: eleveldb:db_ref()
	       }).
%% init
-spec init(Args :: term()) ->
    {ok, State :: term()} | {error, Reason :: term()}.
init(Peer) ->
    LogDir = app_helper:get_env(serv_kv, rafter_root, "rafter"),
    filelib:ensure_dir(LogDir),
    DataFile = filename:join(LogDir, "leveldb"),
    case eleveldb:open(DataFile, [{create_if_missing, true}]) of
	{ok, Db} ->
	    {ok, #state{peer=Peer, db=Db}};
	{error, Reason} ->
	    lager:error("open db error: ~", [Reason]),
	    {error, Reason}
    end.

%% stop backend
-spec stop(State :: term()) ->
    ok | {error, Reason :: term()}.
stop(#state{db=Db}) ->
    eleveldb:close(Db).

%% read op
-spec read(Operation :: term(), State :: term()) ->
    {Value :: term(), State :: term()}.
read({get, Key}, #state{db=Db}=State) when erlang:is_binary(Key) ->
    case eleveldb:get(Db, Key, []) of
	{ok, Value} ->
	    {{ok, Value}, State};
	not_found ->
	    {{error, not_found}, State};
	{error, Reason} ->
	    {{error, Reason}, State}
    end;
read(_BadOperation, State) ->
    {{error, read_badarg}, State}.

%% write op
-spec write(Operation :: term(), State :: term()) ->
    {Value :: term(), State :: term()}.

% put
write({put, Key, Value}=Update, #state{db=Db}=State)
  when erlang:is_binary(Key) andalso erlang:is_binary(Value) ->
    Result = eleveldb:write(Db, [Update], []),
    {Result, State};

% delete
write({delete, Key}=Update, #state{db=Db}=State)
  when erlang:is_binary(Key) ->
    Result = eleveldb:write(Db, [Update], []),
    {Result, State};

write(_BadOperation, State) ->
    {{error, write_badarg}, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
