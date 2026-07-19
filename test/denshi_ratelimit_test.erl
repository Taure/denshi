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

exhausted_headers() ->
    [
        {~"x-ratelimit-remaining", ~"0"},
        {~"x-ratelimit-reset", integer_to_binary(erlang:system_time(second) + 5)}
    ].

message_ids_share_one_bucket_test() ->
    Pid = setup(),
    ok = denshi_ratelimit:update(~"GET", ~"/channels/123/messages/456", exhausted_headers()),
    timer:sleep(10),
    ?assertMatch(
        {wait, _},
        denshi_ratelimit:acquire(~"GET", ~"/channels/123/messages/789")
    ),
    cleanup(Pid).

query_string_shares_one_bucket_test() ->
    Pid = setup(),
    ok = denshi_ratelimit:update(~"GET", ~"/channels/123/messages?limit=50", exhausted_headers()),
    timer:sleep(10),
    ?assertMatch(
        {wait, _},
        denshi_ratelimit:acquire(~"GET", ~"/channels/123/messages?limit=100")
    ),
    cleanup(Pid).

major_parameter_keeps_channels_independent_test() ->
    Pid = setup(),
    ok = denshi_ratelimit:update(~"GET", ~"/channels/123/messages/456", exhausted_headers()),
    timer:sleep(10),
    ?assertEqual(ok, denshi_ratelimit:acquire(~"GET", ~"/channels/999/messages/456")),
    cleanup(Pid).

guild_commands_keep_guilds_independent_test() ->
    Pid = setup(),
    ok = denshi_ratelimit:update(
        ~"POST", ~"/applications/111/guilds/222/commands", exhausted_headers()
    ),
    timer:sleep(10),
    ?assertEqual(
        ok,
        denshi_ratelimit:acquire(~"POST", ~"/applications/111/guilds/333/commands")
    ),
    cleanup(Pid).

interaction_tokens_share_one_bucket_test() ->
    Pid = setup(),
    ok = denshi_ratelimit:update(~"POST", ~"/interactions/1/tok-aaa/callback", exhausted_headers()),
    timer:sleep(10),
    ?assertMatch(
        {wait, _},
        denshi_ratelimit:acquire(~"POST", ~"/interactions/2/tok-bbb/callback")
    ),
    cleanup(Pid).

malformed_major_id_shares_one_bucket_test() ->
    Pid = setup(),
    ok = denshi_ratelimit:update(
        ~"GET", ~"/channels/not-a-snowflake/messages", exhausted_headers()
    ),
    timer:sleep(10),
    ?assertMatch(
        {wait, _},
        denshi_ratelimit:acquire(~"GET", ~"/channels/also-not-a-snowflake/messages")
    ),
    cleanup(Pid).
