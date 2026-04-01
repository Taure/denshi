-module(denshi_dispatcher_test).
-include_lib("eunit/include/eunit.hrl").

-behaviour(denshi_consumer).
-export([init/0, events/0, handle_event/3]).

%% Test consumer implementation

init() ->
    {ok, #{events => []}}.

events() ->
    [message_create, guild_create].

handle_event(EventName, Data, #{events := Events} = State) ->
    {ok, State#{events := [{EventName, Data} | Events]}}.

%% Tests

setup() ->
    {ok, Pid} = denshi_dispatcher:start_link([?MODULE]),
    Pid.

cleanup(Pid) ->
    unlink(Pid),
    exit(Pid, shutdown),
    timer:sleep(10).

dispatch_matching_event_test() ->
    Pid = setup(),
    ok = denshi_dispatcher:dispatch(message_create, #{~"content" => ~"hello"}),
    timer:sleep(50),
    cleanup(Pid).

dispatch_non_matching_event_test() ->
    Pid = setup(),
    ok = denshi_dispatcher:dispatch(typing_start, #{}),
    timer:sleep(50),
    cleanup(Pid).

register_consumer_test() ->
    Pid = setup(),
    ok = denshi_dispatcher:register_consumer(?MODULE),
    timer:sleep(50),
    cleanup(Pid).
