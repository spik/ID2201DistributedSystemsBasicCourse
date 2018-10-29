%% Our first version, called gms1, will only handle starting of a single node and the adding of more nodes.
%% Failures will not be handled so some of the states that we need to keep track of is not described. We will then extend this
%% implementation to handle failures.
%% The group process will when started be a slave but might in the future become a leader. The first process that is started will
%% however become a leader directly.

-module(gms1).

-compile(export_all).

-define(arghh, 100).

%% Initializing a process that is the first node in a group
start(Id) ->
	Self = self(),
	{ok, spawn_link(fun()-> init(Id, Self) end)}.

%% As we only have one node it will be the master, and it is also the leader?????
init(Id, Master) ->
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
			%% This process will be a slave
			slave(Id, Master, Leader, Slaves, Group)
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
		stop ->
			ok
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
