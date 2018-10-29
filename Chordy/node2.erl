-module(node2).

-compile(export_all).

-define(Stabilize,100).
-define(Timeout,1000).

%% Start the first node in the ring
start(Id) ->
	start(Id, nil).

%% Connecting to an existing ring
start(Id, Peer) ->
	timer:start(),
	spawn(fun() -> init(Id, Peer) end).

init(Id, Peer) ->
	%% Set the predecessor to nil
	Predecessor = nil,

	%% Connect to our successor
	{ok, Successor} = connect(Id, Peer),

	%% Schedule the stabilizing procedure; or rather making sure that we send a stabilize message to ourselves
	schedule_stabilize(),

	%% We then call the node/3 procedure that implements the message handling
	node(Id, Predecessor, Successor, storage:create()).

%% This function sets our successor pointer.
%% We are the first node
connect(Id, nil) ->
	%% If we’re all alone we are of course our own successor
	{ok, {Id, self()}};

%% Try to connect to an existing ring
connect(Id, Peer) ->
	Qref = make_ref(),
	%% send a key message to the node that we have been given
	Peer ! {key, Qref, self()},
	receive
		{Qref, Skey} ->
			{ok, {Skey, Peer}}
		after ?Timeout ->
			io:format("Time out: no response~n",[])
		end.

%% A node will have the following properties: a key, a predecessor and a successor
node(Id, Predecessor, Successor, Store) ->
	receive
		%% A peer needs to know our key
		{key, Qref, Peer} ->
			%% Answer the peer with the Id (key)
			Peer ! {Qref, Id},
			node(Id, Predecessor, Successor, Store);

		%% A new node informs us of its existence
		{notify, New} ->
			%% notify returns the predecessor and the updated storage.
			{Pred, UpdatedStore} = notify(New, Id, Predecessor, Store),
			node(Id, Pred, Successor, UpdatedStore);

		%% A predecessor needs to know our predecessor
		{request, Peer} ->
			request(Peer, Predecessor),
			node(Id, Predecessor, Successor, Store);

		stabilize ->
			stabilize(Successor),
			node(Id, Predecessor, Successor, Store);

		%% Create a probe
		probe ->
			create_probe(Id, Successor),
			node(Id, Predecessor, Successor, Store);

		%% Remove probe
		{probe, Id, Nodes, T} ->
			remove_probe(T, Nodes),
			node(Id, Predecessor, Successor, Store);

		%% Forward probe
		{probe, Ref, Nodes, T} ->
			forward_probe(Ref, T, Nodes, Id, Successor),
			node(Id, Predecessor, Successor, Store);

		{add, Key, Value, Qref, Client} ->
			Added = add(Key, Value, Qref, Client,Id, Predecessor, Successor, Store),
			node(Id, Predecessor, Successor, Added);

		{lookup, Key, Qref, Client} ->
			lookup(Key, Qref, Client, Id, Predecessor, Successor, Store),
			node(Id, Predecessor, Successor, Store);

		%% Handover some elements to a new node that joins the ring, i.e. delegate som responsibility
		{handover, Elements} ->
			%% We merge the elements we want the new node to handle with its store.
			Merged = storage:merge(Store, Elements),
			node(Id, Predecessor, Successor, Merged);

		%% Our successor informs us about its predecessor
		{status, Pred} ->
			%% We get a new successor
			Succ = stabilize(Pred, Id, Successor),
			node(Id, Predecessor, Succ, Store);
		state ->
		    io:format(' Id : ~w~n Predecessor : ~w~n Successor : ~w~n', [Id, Predecessor, Successor]),
		    node(Id, Predecessor, Successor, Store);
		stop -> ok;
		_ ->
		    io:format('Strange message received'),
		    node(Id, Predecessor, Successor, Store)
	end.

%% The Pred argument is our successors current predecessor.
%% The stabilize procedure must be done with regular intervals so that new nodes are quickly linked into the ring.
%% Returns our successor
stabilize(Pred, Id, Successor) ->
	%% Successor consists of a key and a pid
	{Skey, Spid} = Successor,

	%% Check the successors predecessor
	case Pred of
		%% It doesn't have one, so we suggest to it that we are it
		nil ->
			%% Notify successor about our existence
			Spid ! {notify, {Id, self()}},
			%% Return our successor
			Successor;
		{Id, _} ->
			%% We are the predesessor, so we just return our successor and doesn't do anyting else.
			Successor;
		%% The successor is its own predecessor
		{Skey, _} ->
			%% Notify successor about our existence
			Spid ! {notify, {Id, self()}},
			%% Return our successor
			Successor;
		%% Predecessor is pointing to another node, with key Xkey and pid Xpid
		{Xkey, Xpid} ->
			%% Check if the new node is between successor and us
			case key:between(Xkey, Id, Skey) of
				%% If it is, we should be behind the predecessor
				true ->
					%% Adopt that node as our successor and stabilize again
					%% Send to Xpid that we are its predecessor, and therefor it is our successor
					Xpid ! {request, self()},
					%% Pred is {Xkey, Xpid}. As this node is our new successor, we return this node.
					Pred;
				%% The node is not between us and our successor, which means that we are its successor and we keep our successor
				false ->
					%% Notify our sucessor of our existence
					Spid ! {notify, {Id, self()}},
					Successor
			end
	end.

%% The stabilize procedure must be done with regular intervals so that new nodes are quickly linked into the ring.
%% Called when a node is created.
schedule_stabilize() ->
	%% Start a timer that sends a stabilize message after a specific time.
	%% send_interval(Time, Pid, Message) -> {ok, TRef}. TRef = A timer reference. Evaluates Pid ! Message repeatedly after Time milliseconds.
	%% Sends message "stabilize" to itself every ?Stabilize milliseconds.
	timer:send_interval(?Stabilize, self(), stabilize).

%% Send a request message to its successor
stabilize({_, Spid}) ->
	Spid ! {request, self()}.

%% A predecessor needs to know our predecessor
request(Peer, Predecessor) ->
	case Predecessor of
		%% We have no predecessor
		nil ->
			%% Tell the peer so
			Peer ! {status, nil};
		%% This is our predecessor
		{Pkey, Ppid} ->
			%% Tell the peer so
			Peer ! {status, {Pkey, Ppid}}
	end.

%% Being notified of a node is a way for a node to make a friendly proposal that it might be our proper predecessor, i.e. that we should be its successor
%% N is the node we want to check if it is our new predecessor
%% This function returns the node that should be our predecessor and the updated storage
notify({Nkey, Npid}, Id, Predecessor, Store) ->
	case Predecessor of
		%% We don't have a predecessor so the new node will be our predecessor
		nil ->
			%% Handover returns the nodes we want to keep
			Keep = handover(Id, Store, Nkey, Npid),

			%% Return our predecessor and the updated storage
			{{Nkey, Npid}, Keep};
		%% We already have a predecessor
		{Pkey, _} ->
			%% Check if this should actually be our predecessor
			case key:between(Nkey, Pkey, Id) of
				%% The new node should be our predecessor, as it is between us and our old predecessor
				true ->
					Keep = handover(Id, Store, Nkey, Npid),
					{{Nkey, Npid}, Keep};
				%% The new node is not between us and our old predecessor
				false ->
					{Predecessor, Store}
			end
	end.

create_probe(Id, Successor)->
	{_, Spid} = Successor,
	Spid ! {probe, Id, [Id], erlang:system_time(micro_seconds)}.

remove_probe(Time, Nodes)->
	TotalTime = erlang:system_time(micro_seconds) - Time,
	%% Print how long it took for the message to go around the node and a list of all nodes in the ring
	io:format("Nodes: ~p~n", [Nodes]),
	io:format("Time: ~w~n", [TotalTime]).

forward_probe(Ref, Time, Nodes, Id, Successor)->
	{_, Spid} = Successor,
	%% Forward the message and add our own Pid to the list of noded
	Spid ! {probe, Ref, Nodes ++ [Id], Time}.

%% To add a new key value we must first determine if our node is the node that should take care of the key.
%% The Qref parameters will be used to tag the return message to the Client.
%% This function returns the store.
add(Key, Value, Qref, Client, Id, {Pkey, _}, {_, Spid}, Store) ->
	%% A node will take care of all adds between itself and its predecessor.
	case key:between(Key, Pkey, Id) of
		true ->
			%% Send an "ok" message to the client with a reference
			Client ! {Qref, ok},

			%% Add to the storage
			storage:add(Key, Value, Store);
		false ->
			%% Not our responsibility, send to successor
			Spid ! {add, Key, Value, Qref, Client},

			%% Just return the unchanged store.
			Store
	end.
%% Same as add but do a lookup instead of adding a value to the store.
lookup(Key, Qref, Client, Id, {Pkey, _}, {_, Spid}, Store) ->
	case key:between(Key, Pkey, Id) of
		true ->
			Result = storage:lookup(Key, Store),
			io:format("Node ~w is responsible for the key~n", [Id]),
			%% Send the result of the lookup to the client
			Client ! {Qref, Result};
		false ->
			Spid ! {lookup, Key, Qref, Client}
	end.

handover(Id, Store, Nkey, Npid) ->
	%% Rest is what we give to the new node.
	%% Keep is what we keep or the old node.
	{Rest, Keep} = storage:split(Id, Nkey, Store),
	%% Handover the "Rest" list to the new node
	Npid ! {handover, Rest},
	%% Return what we want to keep for ourselves.
	Keep.
