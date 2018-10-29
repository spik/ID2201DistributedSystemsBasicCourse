-module(storage).

-compile(export_all).

%% create a new store
create()->
	[].

%%  add a key value pair, return the updated store
add(Key, Value, Store)->
	[{Key, Value}|Store].

%% return a tuple {Key, Value} or the atom false
lookup(Key, Store)->
	lists:keyfind(Key, 1, Store).

%%  return a tuple {Updated, Rest} where the updated store only contains
%%  the key value pairs requested and the rest are found in a list of key-value pairs
split(From, To, Store)->
	%% Partition splits a list in two, one for the entries where the function returns true, and one for when they return false 
	lists:partition(fun({Key,Value})-> key:between(Key, From, To) end, Store).

%% add a list of key-value pairs to a store
merge(Entries, Store)->
	Entries ++ Store.