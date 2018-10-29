-module(node1).

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
	node(Id, Predecessor, Successor).

%% This function sets our successor pointer.
%% We are the first node
connect(Id, nil) ->
	%% If we’re all alone we are of course our own successor
	{ok, {Id, self()}};

%% Try to connect to an existing ring
connect(Id, Peer) ->
	%% Creates a unique reference
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
node(Id, Predecessor, Successor) ->
	receive
		%% A peer needs to know our key
		{key, Qref, Peer} ->
			%% Answer the peer with the Id (key)
			Peer ! {Qref, Id},
			node(Id, Predecessor, Successor);

		%% A new node informs us of its existence
		{notify, New} ->
			%% We get a new predecessor
			Pred = notify(New, Id, Predecessor),
			node(Id, Pred, Successor);

		%% A predecessor needs to know our predecessor
		{request, Peer} ->
			request(Peer, Predecessor),
			node(Id, Predecessor, Successor);

		stabilize ->
			stabilize(Successor),
			node(Id, Predecessor, Successor);

		%% Create a probe
		probe ->
			create_probe(Id, Successor),
			node(Id, Predecessor, Successor);

		%% As the reference matches our Id, we know that we sen the inital probe message,
		%% so the message has been around the ring. We can therfore remove the probe and check how long it took.
		{probe, Id, Nodes, T} ->
			remove_probe(T, Nodes),
			node(Id, Predecessor, Successor);

		%% Forward probe
		{probe, Ref, Nodes, T} ->
			forward_probe(Ref, T, Nodes, Id, Successor),
			node(Id, Predecessor, Successor);

		%% Our successor informs us about its predecessor
		{status, Pred} ->
			%% We see if we should change predecessor
			Succ = stabilize(Pred, Id, Successor),
			node(Id, Predecessor, Succ);
		state ->
		    io:format(" Id : ~w~n Predecessor : ~w~n Successor : ~w~n", [Id, Predecessor, Successor]),
		    node(Id, Predecessor, Successor);
		stop -> ok;
		_ ->
		    io:format("Strange message received"),
		    node(Id, Predecessor, Successor)
	end.

%% The Pred argument is our successor's current predecessor.
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
					%% Send a request message, which means that we will get a message with the Preds predecessor. We then have to stabilize again to know if we should be between
					%% Preds predecessor or not in the same way. We go through the circle until we find our place.
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
%% This function returns the node that should be our predecessor
notify({Nkey, Npid}, Id, Predecessor) ->
	case Predecessor of
		%% We don't have a predecessor so the new node will be our predecessor
		nil ->
			{Nkey, Npid};
		%% We already have a predecessor
		{Pkey, _} ->
			%% Check if this should actually be our predecessor
			case key:between(Nkey, Pkey, Id) of
				%% The new node should be our predecessor, as it is between us and our old predecessor
				true ->
					{Nkey, Npid};
				%% The new node is not between us and our old predecessor
				false ->
					Predecessor
			end
	end.

create_probe(Id, Successor)->
	{_, Spid} = Successor,
	Spid ! {probe, Id, [Id], erlang:system_time(micro_seconds)}.

remove_probe(Time, Nodes)->
	TotalTime = erlang:system_time(micro_seconds) - Time,
	%% Print how long it took for the message to go around the node and a list of all nodes in the ring
	io:format("Nodes: ~p~n", [Nodes]),
	io:format("Node ~w received its own probe. Time: ~w~n", [Id, TotalTime]).

forward_probe(Ref, Time, Nodes, Id, Successor)->
	{_, Spid} = Successor,
	io:format("Node ~w forwarding node ~n", [Id]),
	%% Forward the message and add our own Pid to the list of noded
	Spid ! {probe, Ref, Nodes ++ [Id], Time}.
