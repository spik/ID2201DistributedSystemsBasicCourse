%% This module should keep track of its own counter and pass this along with any message that it sends to other workers. 
%% When receiving a message the worker must update its timer to the greater of its internal clock and the time-stamp of the
%% message before increment its clock.

-module(time).

-compile(export_all).

%% Return an initial Lamport value (could it be 0)
zero()->
	0.

%% Return the time T incremented by one (you will probably ignore the Name but we will use it later)
inc(Name, T)->
	T + 1.

%% merge the two Lamport time stamps (i.e. take the maximum value)
merge(Ti, Tj)->
	if(Ti > Tj)->Ti;
	true->Tj
	end.

%% True if Ti is less than or equal to Tj
leq(Ti, Tj)->
	if(Ti =< Tj)->true;
	true->false
	end.

%% Return a clock that can keep track of the nodes
%% The clock is the loggers data structure that keeps track of the timestamps of the last messages seen from each of the workers
%% List with four elements, one for each worker. One element is a tuple of worker name and its timestamp.
%% [{John, Timestamp}, {Paul, Timestamp}, {Ringo, Timestamp}, {George, Timestamp}]
clock(Nodes)->
	lists:map(fun(Node)->{Node, zero()} end, Nodes).

%% return a clock that has been updated given that we have received a log message from a node at a given time
update(Node, Time, Clock)->
	%% Replace the old time for the node with the new time 
	%% Sort the resulting list so that our clock is sorted
	lists:keysort(2, lists:keyreplace(Node, 1, Clock, {Node, Time})).

%% Is it safe to log an event that happened at a given time, true or false
%% Clock is sorted so we only have to check the first element
%% We know that if the smallest element in the clock is bigger than the Time, the message is safe to print 
safe(Time, [{_, T}|_])->
	leq(Time, T).




