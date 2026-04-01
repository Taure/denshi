-module(denshi_ratelimit_test).
-include_lib("eunit/include/eunit.hrl").

setup() ->
    {ok, Pid} = denshi_ratelimit:start_link(),
    Pid.

cleanup(Pid) ->
    unlink(Pid),
    exit(Pid, shutdown),
    timer:sleep(10).

acquire_no_limit_test() ->
    Pid = setup(),
    ?assertEqual(ok, denshi_ratelimit:acquire(~"GET", ~"/channels/123")),
    cleanup(Pid).

update_and_acquire_test() ->
    Pid = setup(),
    Headers = [
        {~"x-ratelimit-remaining", ~"5"},
        {~"x-ratelimit-reset", integer_to_binary(erlang:system_time(second) + 10)}
    ],
    ok = denshi_ratelimit:update(~"GET", ~"/channels/123", Headers),
    timer:sleep(10),
    ?assertEqual(ok, denshi_ratelimit:acquire(~"GET", ~"/channels/123")),
    cleanup(Pid).

exhausted_bucket_test() ->
    Pid = setup(),
    ResetTime = erlang:system_time(second) + 5,
    Headers = [
        {~"x-ratelimit-remaining", ~"0"},
        {~"x-ratelimit-reset", integer_to_binary(ResetTime)}
    ],
    ok = denshi_ratelimit:update(~"GET", ~"/test/route", Headers),
    timer:sleep(10),
    case denshi_ratelimit:acquire(~"GET", ~"/test/route") of
        {wait, Ms} -> ?assert(Ms > 0);
        ok -> ok
    end,
    cleanup(Pid).

different_routes_independent_test() ->
    Pid = setup(),
    ResetTime = erlang:system_time(second) + 5,
    Headers = [
        {~"x-ratelimit-remaining", ~"0"},
        {~"x-ratelimit-reset", integer_to_binary(ResetTime)}
    ],
    ok = denshi_ratelimit:update(~"GET", ~"/route/a", Headers),
    timer:sleep(10),
    ?assertEqual(ok, denshi_ratelimit:acquire(~"GET", ~"/route/b")),
    cleanup(Pid).
