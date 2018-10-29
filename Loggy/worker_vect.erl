
-module(worker_vect).

-compile(export_all).

%% The worker is given a unique name and access to the logger. 
%% We also provide the worker with a unique value to seed its random generator.
%% The sleep value will determine how active the worker is sending messages
%% The jitter value will introduce a random delay between the sending of a message and the sending of a log entry.
start(Name, Logger, Seed, Sleep, Jitter) ->
	spawn_link(fun() -> init(Name, Logger, Seed, Sleep, Jitter) end).

stop(Worker) ->
	Worker ! stop.

%% The upstart phase in init/2 is there so that we can start all workers and then inform them who their peers are. 
init(Name, Log, Seed, Sleep, Jitter) ->
	%% seed/3 seeds random number generation with integer values in the process dictionary, and returns the old state.
	random:seed(Seed, Seed, Seed),
	receive
		%% Inform the worker who its peers (the other workers) are
		{peers, Peers} ->
			loop(Name, Log, Peers, Sleep, Jitter, vect:zero());
		stop ->
			ok
	end.

%% Sends a message to the worker process informing it of its peers. 
peers(Wrk, Peers) ->
	Wrk ! {peers, Peers}.

%% The worker process will wait for either a message from one of its peers or after a random sleep time select a peer
%% process that is sent a message.
loop(Name, Log, Peers, Sleep, Jitter, MyVector)->
	Wait = random:uniform(Sleep),
	%% To keep track of what is happening and in what order things are done 
	%% we send a log entry to the logger every time we send or receive a message.
	%% Wait to receive a message from a worker
	receive
		{msg, ReceivedVector, Msg} ->
			%% When we recieve a message, use the bigger timestamp of the time recieved in the message and the local time, and increment the time
			NewMyVector = vect:inc(Name, vect:merge(MyVector, ReceivedVector)),
			
			%% Log the message received, including the new lamport time, i.e. the latest time. 
			Log ! {log, Name, NewMyVector, {received, Msg}},
			
			%% Call loop again with the new time
			loop(Name, Log, Peers, Sleep, Jitter, NewMyVector);
		stop ->
			ok;
		Error ->
			Log ! {log, Name, time, {error, Error}}
	%% If no matching messages has arrived after "Wait" amount of time, send a message to a random worker. 
	after Wait ->
			Selected = select(Peers),
			
			%% Increment the time
			NewMyVector = vect:inc(Name, MyVector),
			
			%% The messages include a unique random value so that we can track the sending and receiving of a message.
			Message = {hello, random:uniform(100)},
			
			%% Send the message with the incremented time
			Selected ! {msg, NewMyVector, Message},
			jitter(Jitter),
			
			%% Log the message sent with the incremented time
			Log ! {log, Name, NewMyVector, {sending, Message}},
			loop(Name, Log, Peers, Sleep, Jitter, NewMyVector)
	end.

%% nth(N, List) -> Returns the Nth element of List
%% random:uniform(N)-> Given an integer N >= 1, returns a random integer uniformly distributed between 1 and N.
%% length(List)-> Returns the length of List.
%% Returns a random worker from the lsit of workers
select(Peers) ->
	lists:nth(random:uniform(length(Peers)), Peers).

%% jitter introduces a slight delay between sending the message to the peer and informing the logger. 
%% If we don't introduce a delay here we would hardly ever have messages occur out of order when 
%% running in the same virtual machine
jitter(0) -> ok;
jitter(Jitter) -> timer:sleep(random:uniform(Jitter)).


