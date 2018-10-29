%% @author Charlotta
%% @doc @todo Add description to vect.


-module(vect).

-compile(export_all).

%% Return an initial Lamport vector value
zero()->
	[].

%% Increment the timestamp for the worker with the specified name 
inc(Name, Time) ->
	%% Find the worker in the vector
	case lists:keyfind(Name, 1, Time) of
		{Name, Timestamp} ->
			%% Increment the timestamp for the worker
			lists:keyreplace(Name, 1, Time, {Name, Timestamp+1});
		false ->
			%% If the worker isn't already in the vecor, add it with the timestamp 1 (as we want to increment the timestamp)
			[{Name, 1}|Time]
	end.

%% We want the maximum timestamp for all the workers. We go through all the workers and compare their timestamps. 
merge([], ReceivedVector) ->
	ReceivedVector;
merge([{Name, Ti}|Rest], ReceivedVector) ->
	%% First, find the worker whose timestamp we want to compare 
	case lists:keyfind(Name, 1, ReceivedVector) of
		{Name, Tj} ->
			%% If we get a match, we add the worker with the highest timestamp and removes the old entry
			[{Name, erlang:max(Ti, Tj)} |merge(Rest, lists:keydelete(Name, 1, ReceivedVector))];
		false ->
			%% Otherwise, we just add the worker to the list
			[{Name, Ti}|merge(Rest, ReceivedVector)]
	end.

%% Compare the timestamps. Return true if Tj is less than or equal to Tj.
%% We have now gone though the whole vector without finding a timestamp that is higher, which means all worker timestamps are lower and we return true.
leq([], _) ->
	true;
leq([{Name, Ti}|Rest],Clock) ->
	%% UNECESSARY!!
	%% SortedTime = lists:keysort(2, Time),
	
	%% Find the worker whose timestamp we want to compare to the clock
	case lists:keyfind(Name, 1, Clock) of
		{Name, Tj} ->
			if
				Ti =< Tj ->
					%% In this case, at least one of the workers has a lower time stamp. Call leq again to check the other workers too. 
					leq(Rest, Clock);
				true ->
					%% At least one of the workers has a higher time stamp, which means that the whole vector timestamp is not smaller.
					false
			end;
		false ->
			%% If no entry exist for this name, it means that the timestamp is implicitly 0, which is lower than at lesat 1 that an existing entry has  
			false
	end.

%% Clock is a list of tuples, each tuple containing the highest timestamps for each worker. 
%% So for each worker the clock has the highest timestamp for that worker of all timestamps in all vectors. 
clock(_) ->
	[]. 

%% Update the clock, as the worker has just incemented it's clock before sending a log message to the logger. 
%% From is the process that sent the message to logger, and received a message from another process in worker module
%% Time is the vector clock of process "From"
update(From, Time, Clock) ->
	%% Find the worker who the message is from in time
	%% This is the tuple {Worker, Timestamp} for the worker in the vector for that worker. 
	Worker = lists:keyfind(From, 1, Time),
	
	%% Find the worker in the clock
	case lists:keyfind(From, 1, Clock) of
		{From, _} ->
			%% Replace the old entry with the new entry 
			lists:keyreplace(From, 1, Clock, Worker);
		false ->
			%% In this case, the worker did not already exist in the clock så we just add it. 
			[Worker| Clock]
	end.

safe(Time, Clock) ->
	leq(Time, Clock).
