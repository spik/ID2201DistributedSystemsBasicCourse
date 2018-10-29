%% This benchmark program sends 100 requests to our server and measures the time it takes to receive a response. 
-module(test).

-export([bench/2]).

%% Spawn N number of threads recursively
spawn_threads(0, _)-> ok;
spawn_threads(N, Listen)->
    spawn(rudy, request, [Listen]),
    spawn_threads(N - 1, Listen).

%% Measures the time it takes to run the program
bench(Host, Port) ->
	%% erlang:system_time returns current Erlang system time converted into the Unit passed as argument.
	Start = erlang:system_time(micro_seconds),
	run(100, Host, Port),
	Finish = erlang:system_time(micro_seconds),
	Finish - Start.

%% This function makes the program run N times so that we can measure the time for a N different executions
run(N, Host, Port) ->
	if
		N == 0 ->
			ok;
		true ->
			connect(Host, Port),
			run(N-1, Host, Port)
	end.

connect(Host, Port) ->
	Opt = [list, {active, false}, {reuseaddr, true}],
	
	%% Connects to a server on TCP port Port on the host with IP address Address(Host), i.e. connects to the specified host on the specified port.
	%% Address/Host can be either a host or an IP address
	%% Returns a socket 
	{ok, Server} = gen_tcp:connect(Host, Port, Opt),
	
	%%spawn_threads(10, Server),
	request(Server).

%% This is our client. It sends a request to the server and gets a response
request(Server) ->
	
	%% Sends a packet (http:get("foo")) to the specified socket (Server)
	%% http:get generates a GET request with the specified URI (foo)
	gen_tcp:send(Server, http:get("foo")),

	%% Receive a respons from the server. Receives a packet from a socket and returns the packet that was received. 
	%% 0 means that we want to read all available bytes
	Recv = gen_tcp:recv(Server, 0),
	case Recv of
		{ok, _} ->
			ok;
		{error, Error} ->
			io:format("test: error: ~w~n", [Error])
	end,
	gen_tcp:close(Server).

send_requests(Server) ->
	ok.

%% Takes 4,968984 seconds for 100 requests => ca 25 requests per second (0,04968984 seconds per request). 
%% 94000 microseconds = 0,094 seconds without the artificial delay => big difference! Answer: yes it is significant. 
%% 9,906097 when running two benchmarks (200 requests) to the same server. Almost twice as long time. 
%% With parallel server and sending 200 requests (100 from two machines), it takes 4687995 ms. 