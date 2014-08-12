serv_kv
=======
   _serv_kv_ -- riak_core and riak_ensemble based Key/Value store.

   Required: OTP17 and above.

   1, start N peer
   2, in any peer do
	   Nodes = [node() | nodes()],
	   serv_kv:set_config(Nodes).
   3, in peer A do
	   serv_kv:put(<<"lee">>, <<"li">>).
   4, in peer B do
	   serv_kv:get(<<"lee">>).
       {ok,<<"li">>}
