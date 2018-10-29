
-module(gms4).

-compile(export_all).

-define(timeout, 1000).
-define(arghh, 1000).
-define(riskOfLosingMessage, 100).

%% Initializing a process that is the first node in a group
start(Id) ->
	Rnd = random:uniform(1000),
	Self = self(),
	{ok, spawn_link(fun()-> init_leader(Id, Rnd, Self) end)}.

%% As we only have one node it will be the master, and it is also the leader?????
init_leader(Id, Rnd, Master) ->
	%% How does this make processes not crashing at the same time?
	random:seed(Rnd, Rnd, Rnd),

	%% As it is the first node we have an empty list of peers
	leader(Id, Master, 0, [], [Master]).

start(Id, Grp) ->
	Self = self(),
	{ok, spawn_link(fun()-> init(Id, Grp, Self) end)}.

init(Id, Grp, Master) ->
	Self = self(),

	%% We need to send a {join, Master, self()} message to a node in the group and wait for an invitation.
	Grp ! {join, Master, Self},
	receive
		%% The invitation is delivered as a view message containing everything we need to know.
		{view, N, [Leader|Slaves], Group} ->
			Leader ! {ack, self()},
			Master ! {view, Group},

			%% The only node that will be monitored is the leader
			erlang:monitor(process, Leader),

			%% This process will be a slave
			%% {view, [Leader|Slaves], Group} is the last message received, so we call slave with this message
			slave(Id, Master, Leader, N+1, {view, N, [Leader|Slaves], Group}, Slaves, Group)

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
%% ListOfMessages: A list with all the messages sent by the master. This is so that if a message is lost, we can just send it again. 
leader(Id, Master, N, Slaves, Group) ->
	receive
		%% a message either from its own master or from a peer node.
		{mcast, Msg} ->
			%% Broadcast the message to all peers
			bcast(Id, {msg, N, Msg}, Slaves),

			%% Send the message to the application layer (i.e. the master)
			Master ! Msg,
			leader(Id, Master, N+1, Slaves, Group);

		%% A message, from a peer or the master, that is a request from a node to join the group.
		%% Wrk: the process identifier of the application layer
		%% Peer: the process identifier of its group process
		{join, Wrk, Peer} ->
			%% Append the peers to the list of slaves
			Slaves2 = lists:append(Slaves, [Peer]),

			%% Add the application layer to the group?
			Group2 = lists:append(Group, [Wrk]),

			%% Broadcast a message with the new slaves, adding ourselves first in the list (as we are the leader), and the new group.
			bcast(Id, {view, N, [self()|Slaves2], Group2}, Slaves2),

			%%Send message to the application layer with the new group
			Master ! {view, Group2},
			leader(Id, Master, N+1, Slaves2, Group2);
		stop ->
			ok
	end.

%% The state of a slave is exactly the same as for the leader with the only exception that the slaves keep explicit track of the leader.
%% Forward messages from its master to the leader and vice versa
%% N is the expected sequence number of the next message
%% Last is a copy of the last message
slave(Id, Master, Leader, N, Last, Slaves, Group) ->
	receive
		%% A request from its master to multicast a message
		{mcast, Msg} ->
			%% Forward the message to the leader
			Leader ! {mcast, Msg},
			slave(Id, Master, Leader, N, Last, Slaves, Group);

		%% a request from the master to allow a new node to join the group
		{join, Wrk, Peer} ->
			%% Forward the message to the leader
			Leader ! {join, Wrk, Peer},
			slave(Id, Master, Leader, N, Last, Slaves, Group);

		%% a multicasted message from the leader
		{msg, N, Msg} ->
			Leader ! {ack, self()},
			Master ! Msg,
			slave(Id, Master, Leader, N+1, {msg, N, Msg}, Slaves, Group);

		%% Since this message has a lower count, it is old and can be discarded
		%% Therefor, we do not increment N nor do we add the message as last message
		{msg, I, _} when I < N->
			Leader ! {ack, self()},
	    	slave(Id, Master, Leader, N, Last, Slaves, Group);

		%% a multicasted view from the leader
		{view, N, [Leader|Slaves2], Group2} ->
			Leader ! {ack, self()},
			Master ! {view, Group2},
			slave(Id, Master, Leader, N+1, {view, N, [Leader|Slaves2], Group2}, Slaves2, Group2);

		%% We receive a DOWN message from the monitor, which means that the leader has died (as it is the only process being monitored)
		{'DOWN', _Ref, process, Leader, _Reason} ->
			%% Hold an election to elect a new leader
			election(Id, Master, N, Last, Slaves, Group);
		stop ->
			ok
	end.

election(Id, Master, N, Last, Slaves, [_|Group]) ->
	Self = self(),
	case Slaves of
		%% I am the first node in the list, I am the new leader
		[Self|Rest] ->

			%%  forward the last received message to all peers in the group
			%%  This means that if the last leader crashed before a broadcast was completed, 
			%%  the broadcast message will be sent again so that everyone receives the message and all nodes are in sync.
			bcast(Id, Last, Rest),
			bcast(Id, {view, N, Slaves, Group}, Rest),
			Master ! {view, Group},

			%% Call leader as I am the leader
			leader(Id, Master, N+1, Rest, Group);

		%% The first node in the list is the new leader
		[Leader|Rest] ->
			%% Monitor the new leader
			erlang:monitor(process, Leader),

			%% I am now a slave
			slave(Id, Master, Leader, N, Last, Rest, Group)
	end.

bcast(Id, Msg, Nodes) ->
	lists:foreach(fun(Node) -> send(Node, Msg), crash(Id) end, Nodes).

send(Node, Msg)->
	%% Decide if a message will be lost
	case random:uniform(?riskOfLosingMessage) of
    	?riskOfLosingMessage -> 
    		%% If we get to the case where a message should be lost, we just don't send message, simulating that it was lost. 
    		io:format("Message ~w was lost ~n", [Msg]);
    	_ -> 
    		%% otherwise we just send the message
    		Node ! Msg
    end,
    %% In either case, we wait to receive an ack
	receive 
		%% An ack was received so everything is ok
		{ack, Node} -> ok
	after 100 ->
		%% After waiting 100 ms, we assume the message was lost and just resend it. 
		send(Node, Msg)
	end.

crash(Id) ->
	%% ?arghh defines the risk of crashing. Choose a random value between 0 and arghh
	case random:uniform(?arghh) of
		%% If it is arghh, the system will crash
		?arghh ->
			io:format("leader ~w: crash~n", [Id]),
			exit(no_luck);
		_ ->
			ok
	end.


