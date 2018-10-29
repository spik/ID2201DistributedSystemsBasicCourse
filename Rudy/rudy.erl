
-module(rudy).

-compile(export_all).

%% Called to start the program
start(Port) ->
	%% Registers the name "rudy" to the process that we spawn by calling init with the port. 
	register(rudy, spawn(fun() -> init(Port) end)).

%% Spawn N number of threads recursively
spawn_threads(0, _)-> ok;
spawn_threads(N, Listen)->
    spawn(rudy, handler, [Listen]),
    spawn_threads(N - 1, Listen).

%%Called to stop the program
stop() ->
	%% Whereis takes the registered name and returns the pid for that name. 
	%% Exit sends an exit signal with exit reason Reason ("time to die") to the process or port identified by Pid.
	exit(whereis(rudy), "time to die").

%% Initializes the server, takes a port number, opens a listening socket
%% and passes the socket to handler/1. 
init(Port) -> 
	%% These options specifies that we will see the bytes as a list of integers instead of a binary structure.
	%% We will need to read the input using recv/2 rather than having it sent to us as messages.
	%% The port address should be used again and again
	Opt = [list, {active, false}, {reuseaddr, true}],
	
	%% This is how a listening socket is opened by the server.
	%% Sets up a socket to listen on the port "Port" on the local host.
	%% Returns a socket 
	case gen_tcp:listen(Port, Opt) of
		{ok, ListenSocket} ->
			spawn_threads(10, ListenSocket),
			handler(ListenSocket),
			gen_tcp:close(ListenSocket),
			ok;
		{error, Error} ->
			error
	end.

%% Listens to the socket for an incoming connection.
%% Once a client has connect it will pass the connection to request/1.
handler(ListenSocket) ->
	%% this is how we accept an incoming request.
	%% If it succeeds we will have a communication channel open to the client.
	%% Accepts an incoming connection request on a listen socket. Socket must be a socket returned from listen/2. 
	%% Returns {ok, Socket} if a connection is established
	case gen_tcp:accept(ListenSocket) of
		{ok, Client} ->
			request(Client),
			
			%% Call handler again recursively so that we can handle several requests 
			handler(ListenSocket);
		{error, Error} ->
			error
	end.

%% Reads the request from the client connection.
%% It will then parse the request using your http parser and pass the request to reply/1.
%% The reply is then sent back to the client. 
request(Client) ->
	%% This function receives a packet from a socket in passive mode. 
	%% Returns the packet/request that was sent from the client
	%% 0 specifies that we want to return all available bytes. 
	Recv = gen_tcp:recv(Client, 0),
	case Recv of
		%% Str is a string which is the request we got from the client
		{ok, Str} ->
			%% Print the request that was received
			%%io:format("~s~n", [Str]),
			%% Parse our request with our http parser
			Request = http:parse_request(Str),
			Response = reply(Request),
			
			%% Sends the reply packet (reponse) to the client via the socket (Client).
			%% Returns "ok"
			gen_tcp:send(Client, Response);
		{error, Error} ->
			io:format("rudy: error: ~w~n", [Error])
	end,
	gen_tcp:close(Client).

%%Sends a reply to the request. 
reply({{get, URI, _}, _, _}) ->
	%% Small delay to simulate file handling, server side scripting etc.
	timer:sleep(40),
	http:ok("Everything works").

%% erl -name foo@130.237.250.69
%% rudy:init(8080).

