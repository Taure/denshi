-module(denshi_heartbeat_test).
-include_lib("eunit/include/eunit.hrl").

setup() ->
    {ok, Pid} = denshi_heartbeat:start_link(),
    Pid.

cleanup(Pid) ->
    unlink(Pid),
    exit(Pid, shutdown),
    timer:sleep(10).

start_beating_sends_heartbeat_test() ->
    Pid = setup(),
    denshi_heartbeat:start_beating(self(), 100),
    receive
        send_heartbeat -> ok
    after 500 ->
        ?assert(false)
    end,
    cleanup(Pid).

ack_resets_missed_test() ->
    Pid = setup(),
    denshi_heartbeat:start_beating(self(), 100),
    receive
        send_heartbeat -> ok
    after 500 -> ?assert(false)
    end,
    denshi_heartbeat:ack(),
    receive
        send_heartbeat -> ok
    after 500 -> ?assert(false)
    end,
    cleanup(Pid).

stop_beating_test() ->
    Pid = setup(),
    denshi_heartbeat:start_beating(self(), 50),
    receive
        send_heartbeat -> ok
    after 500 -> ?assert(false)
    end,
    denshi_heartbeat:stop_beating(),
    receive
        send_heartbeat -> ?assert(false)
    after 200 ->
        ok
    end,
    cleanup(Pid).
