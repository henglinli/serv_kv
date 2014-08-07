-module(serv_kv_sup).

-behaviour(supervisor).

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
    VMaster = {riak_kv_vnode_master,
               {riak_core_vnode_master, start_link,
                [riak_kv_vnode, riak_kv_legacy_vnode, riak_kv]},
               permanent, 5000, worker, [riak_core_vnode_master]},

    EntropyManager = {riak_kv_entropy_manager,
                      {riak_kv_entropy_manager, start_link, []},
                      permanent, 30000, worker, [riak_kv_entropy_manager]},

    EnsemblesKV =  {riak_kv_ensembles,
                    {riak_kv_ensembles, start_link, []},
                    permanent, 30000, worker, [riak_kv_ensembles]},

    
    % Figure out which processes we should run...
    HasStorageBackend = (app_helper:get_env(serv_kv, storage_backend) /= undefined),
    %% Build the process list...
    Processes = lists:flatten([
			       ?IF(HasStorageBackend, VMaster, []),
			       EntropyManager,
			       [EnsemblesKV || riak_core_sup:ensembles_enabled()]
			      ]),

    {ok, { {one_for_one, 5, 10}, Processes} }.

