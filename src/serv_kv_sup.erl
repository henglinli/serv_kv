-module(serv_kv_sup).

-behaviour(supervisor).

-include_lib("rafter/include/rafter_opts.hrl").

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define (IF (Bool, A, B), if Bool -> A; true -> B end).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    VMaster = {serv_kv_vnode_master,
               {riak_core_vnode_master, start_link, [serv_kv_vnode]},
               permanent, 5000, worker, [riak_core_vnode_master]},
    
    %% Figure out which processes we should run...
    HasStorageBackend = (app_helper:get_env(serv_kv, storage_backend) /= undefined),
    %% rafter
    Backend = app_helper:get_env(serv_kv, storage_backend, serv_kv_backend_eleveldb),
    LogDir = app_helper:get_env(serv_kv, rafter_root, "rafter"),
    filelib:ensure_dir(LogDir),
    Opts = #rafter_opts{state_machine=Backend, logdir=LogDir},

    Rafter = {serv_kv_rafter_sup,
	      {rafter_consensus_sup, start_link, 
	       [{serv_kv_rafter, erlang:node()}, Opts]},
	      permanent, 5000, supervisor, [rafter_consensus_sup]},

    %% Build the process list...
    Processes = lists:flatten([
			       ?IF(HasStorageBackend, VMaster, []),
			       Rafter
			      ]),

    {ok, { {one_for_one, 5, 10}, Processes} }.

