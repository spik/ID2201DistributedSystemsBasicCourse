
-module(http).

-compile(export_all).

parse_request(R0) ->
	{Request, R1} = request_line(R0),
	{Headers, R2} = headers(R1),
	{Body, _} = message_body(R2),
	{Request, Headers, Body}.

%% The request line consists of: a method, a request URI and a http version, all seperated by space and
%% terminated by carrige return line feed (new line)
%% Space is 32 in ascii
%% The message can be GET, HEAD etc. 
%% The first part of the request is GET . The rest (R0) is URI, version and carrige return line feed.
request_line([$G, $E, $T, 32 |R0]) ->
	{URI, R1} = request_uri(R0),		%% Get the URI. The rest of the request after this is R1.
	{Ver, R2} = http_version(R1),		%% Get the http version. The rest of the request after this is R2.
	[13,10|R3] = R2,					%% R2 consists of carrige return line feed and R3 (which is headers and body)
	{{get, URI, Ver}, R3}.				%% Return the request

%% Parse the URI and return it as a string. 
%% When we get to a space we know the URI is ended
request_uri([32|R0])->
	{[], R0};
%% Otherwise we get the next character in the URI
request_uri([C|R0]) ->
	{Rest, R1} = request_uri(R0),		%% Get the rest of the characters one by one by calling request_URI again
	{[C|Rest], R1}.						%% Return value that is done "on the way back" from the recursive call

%% HTTP version can be either 1.0 or 1.1. 
http_version([$H, $T, $T, $P, $/, $1, $., $1 | R0]) ->
	{v11, R0};
http_version([$H, $T, $T, $P, $/, $1, $., $0 | R0]) ->
	{v10, R0}.

%% Go through all headers 
headers([13,10|R0]) ->
	{[],R0};
headers(R0) ->
	{Header, R1} = header(R0),
	{Rest, R2} = headers(R1),
	{[Header|Rest], R2}.

%% Go through a single header
header([13,10|R0]) ->
	{[], R0};
header([C|R0]) ->
	{Rest, R1} = header(R0),
	{[C|Rest], R1}.

message_body(R) ->
	{R, []}.

%% Generate an OK reponse
ok(Body) ->
	"HTTP/1.1 200 OK\r\n" ++ "\r\n" ++ Body.

%% Generate a GET request
get(URI) ->
	%% We need two \r\n, one to end the request line and one to end the header section. 
	"GET " ++ URI ++ " HTTP/1.1\r\n" ++ "\r\n".
