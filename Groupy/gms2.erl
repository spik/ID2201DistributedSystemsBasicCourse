
-module(gms2).

-compile(export_all).

-define(timeout, 1000).
-define(arghh, 100).

%% Initializing a process that is the first node in a group
start(Id) ->
	Rnd = random:uniform(1000),
	Self = self(),
	{ok, spawn_link(fun()-> init_leader(Id, Rnd, Self) end)}.

%% As we only have one node it will be the master, and it is also the leader?????
init_leader(Id, Rnd, Master) ->
	%% How does this make processes not crashin at the same time?
	random:seed(Rnd, Rnd, Rnd),

	%% As it is the first node we have an empty list of peers
	leader(Id, Master, [], [Master]).

start(Id, Grp) ->
	Self = self(),
	{ok, spawn_link(fun()-> init(Id, Grp, Self) end)}.

init(Id, Grp, Master) ->
	Self = self(),

	%% We need to send a {join, Master, self()} message to a node in the group and wait for an invitation.
	Grp ! {join, Master, Self},
	receive
		%% The invitation is delivered as a view message containing everything we need to know.
		{view, [Leader|Slaves], Group} ->
			Master ! {view, Group},

			%% The only node that will be monitored is the leader
			erlang:monitor(process, Leader),

			%% This process will be a slave
			slave(Id, Master, Leader, Slaves, Group)

	%% Since the leader can crash it could be that a node that wants to join the group will never receive a reply.
	%% Therefore, we only wait a certain amount of time for a reponse
	after ?timeout ->
		%% send an error message to the master when a reply is not received
		Master ! {error, "no reply from leader"}
	end.


%% Id: a unique name, of the node, only used for debugging
%% Master: the process identifier of the application layer
%% Slaves: an ordered list of the process identifiers of all slaves in the group.
%% based on when they were admitted to the group.
%% Group: a list of all application layer processes in the group
leader(Id, Master, Slaves, Group) ->
	receive
		%% a message either from its own master or from a peer node.
		{mcast, Msg} ->
			%% Broadbast the message to all peers
			bcast(Id, {msg, Msg}, Slaves),

			%% Send the message to the applicaiton layor (i.e. the master)
			Master ! Msg,
			leader(Id, Master, Slaves, Group);

		%% A message, from a peer or the master, that is a request from a node to join the group.
		%% Wrk: the process identifier of the application layer
		%% Peer: the process identifier of its group process
		{join, Wrk, Peer} ->
			%% Append the peers to the list of slaves
			Slaves2 = lists:append(Slaves, [Peer]),

			%% Add the applicaiton layor to the group? FR�GA! Skillnaden p� group och slaves? eller vad inneh�ller group?
			Group2 = lists:append(Group, [Wrk]),

			%% Broadcast a message with the new slaves, adding ourselves first in the list (as we are the leader), and the new group.
			bcast(Id, {view, [self()|Slaves2], Group2}, Slaves2),

			%%Send message to the application layor with the new group
			Master ! {view, Group2},
			leader(Id, Master, Slaves2, Group2);
		stop ->
			ok
	end.

%% The state of a slave is exactly the same as for the leader with the only exception that the slaves keep explicit track of the leader.
%% Forward messages from its master to the leader and vice versa
slave(Id, Master, Leader, Slaves, Group) ->
	receive
		%% A request from its master to multicast a message
		{mcast, Msg} ->
			%% Forward the message to the leader
			Leader ! {mcast, Msg},
			slave(Id, Master, Leader, Slaves, Group);
		%% a request from the master to allow a new node to join the group

		{join, Wrk, Peer} ->
			%% Forward the message to the leader
			Leader ! {join, Wrk, Peer},
			slave(Id, Master, Leader, Slaves, Group);

		%% a multicasted message from the leader
		{msg, Msg} ->
			%% Send the message to the master
			Master ! Msg,
			slave(Id, Master, Leader, Slaves, Group);

		%% a multicasted view from the leader
		{view, [Leader|Slaves2], Group2} ->
			Master ! {view, Group2},
			slave(Id, Master, Leader, Slaves2, Group2);
		%% We receive a DOWN message from the monitor, which means that the leader has died (as it is the only process being monitored)
		{'DOWN', _Ref, process, Leader, _Reason} ->
			%% Hold an election to elect a new leader
			election(Id, Master, Slaves, Group);
		stop ->
			ok
	end.

election(Id, Master, Slaves, [_|Group]) ->
	Self = self(),
	case Slaves of
		%% I am th efirst node in te list, I am the new leader
		[Self|Rest] ->
			%% Broadcast a message saying I am the new leader
			bcast(Id, {view, Slaves, Group}, Rest),

			%% And inform the master
			Master ! {view, Group},

			%% Call eader as I am the leader
			leader(Id, Master, Rest, Group);

		%% The first node in the list is the new leader
		[Leader|Rest] ->
			%% Moitor the new leader
			erlang:monitor(process, Leader),

			%% I am now a slave
			slave(Id, Master, Leader, Rest, Group)
	end.

bcast(Id, Msg, Nodes) ->
	lists:foreach(fun(Node) -> Node ! Msg, crash(Id) end, Nodes).

crash(Id) ->
	%% ?arghh defines the risk of crashing. Choose a random value between 0and arghh
	case random:uniform(?arghh) of
		%% If it is arghh, the system will crash
		?arghh ->
			io:format("leader ~w: crash~n", [Id]),
			exit(no_luck);
		_ ->
			ok
	end.
