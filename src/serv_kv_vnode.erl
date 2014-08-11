-module(serv_kv_vnode).
-behaviour(riak_core_vnode).

-include_lib("riak_core/include/riak_core_vnode.hrl").
-include_lib("rafter/include/rafter_opts.hrl").

-export([start_vnode/1,
         init/1,
         terminate/2,
         handle_command/3,
         is_empty/1,
         delete/1,
         handle_handoff_command/3,
         handoff_starting/2,
         handoff_cancelled/1,
         handoff_finished/2,
         handle_handoff_data/2,
         encode_handoff_item/2,
         handle_coverage/4,
         handle_exit/3]).

-ignore_xref([
             start_vnode/1
             ]).

-record(state, {partition :: partition(),
                rafter :: atom()
               }).

%% API
start_vnode(I) ->
    riak_core_vnode_master:get_vnode_pid(I, ?MODULE).

-spec init([partition()]) ->
                  {ok, ModState :: term()} |
                  {ok, ModState :: term(), [term()]} |
                  {error, Reason :: term()}.
init([Partition]) ->
    Rafter = name(Partition),
    Backend = app_helper:get_env(serv_kv, storage_backend, serv_kv_backend_eleveldb),
    LogDir = app_helper:get_env(serv_kv, log_dir, "./serv_kv_log"),
    Opts = #rafter_opts{state_machine=Backend, logdir=LogDir},
    case rafter:start_node(Rafter, Opts) of
        {ok, _Pid} ->
            {ok, #state{partition=Partition, rafter=Rafter}};
        {error, Reason} ->
            {error, Reason}
    end.

%% Sample command: respond to a ping
handle_command(ping, _Sender, State) ->
    {reply, {pong, State#state.partition}, State};

handle_command(Message, _Sender, State) ->
    lager:warnning("unknown command ~p", [Message]),
    {noreply, State}.

handle_handoff_command(_Message, _Sender, State) ->
    {noreply, State}.

handoff_starting(_TargetNode, State) ->
    {true, State}.

handoff_cancelled(State) ->
    {ok, State}.

handoff_finished(_TargetNode, State) ->
    {ok, State}.

handle_handoff_data(_Data, State) ->
    {reply, ok, State}.

encode_handoff_item(_ObjectName, _ObjectValue) ->
    <<>>.

is_empty(State) ->
    {true, State}.

delete(State) ->
    {ok, State}.

handle_coverage(_Req, _KeySpaces, _Sender, State) ->
    {stop, not_implemented, State}.

handle_exit(_Pid, _Reason, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.
%% ===================================================================
%% Private Functions
%% ===================================================================
name(Partition) ->
    Name = "serv_kv_vnode-" ++ erlang:integer_to_list(Partition),
    erlang:list_to_atom(Name).
