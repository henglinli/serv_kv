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
    VMaster = {serv_kv_vnode_master,
               {riak_core_vnode_master, start_link,
                [serv_kv_vnode]},
               permanent, 5000, worker, [riak_core_vnode_master]},
    
    % Figure out which processes we should run...
    HasStorageBackend = (app_helper:get_env(serv_kv, storage_backend) /= undefined),
    %% Build the process list...
    Processes = lists:flatten([
			       ?IF(HasStorageBackend, VMaster, [])
			      ]),

    {ok, { {one_for_one, 5, 10}, Processes} }.

