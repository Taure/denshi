-module(denshi_ratelimit).
-behaviour(gen_server).

-export([start_link/0, acquire/2, update/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(TAB, denshi_ratelimit_buckets).
-define(GLOBAL_LIMIT, 50).
-define(GLOBAL_KEY, <<"__global__">>).

-spec start_link() -> gen_server:start_ret().
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec acquire(binary(), binary()) -> ok | {wait, non_neg_integer()}.
acquire(Method, Route) ->
    Key = bucket_key(Method, Route),
    Now = erlang:system_time(second),
    case check_global(Now) of
        {wait, _} = Wait ->
            Wait;
        ok ->
            case ets:lookup(?TAB, Key) of
                [{Key, 0, Reset}] when Reset > Now ->
                    {wait, (Reset - Now) * 1000};
                _ ->
                    ok
            end
    end.

-spec update(binary(), binary(), [{binary(), binary()}]) -> ok.
update(Method, Route, Headers) ->
    gen_server:cast(?MODULE, {update, bucket_key(Method, Route), Headers}).

%% gen_server callbacks

init([]) ->
    _ = ets:new(?TAB, [named_table, protected, set, {read_concurrency, true}]),
    schedule_global_reset(),
    {ok, #{global_count => 0}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({update, Key, Headers}, State) ->
    Remaining = find_header(~"x-ratelimit-remaining", Headers),
    Reset = find_header(~"x-ratelimit-reset", Headers),
    case {Remaining, Reset} of
        {undefined, _} ->
            ok;
        {_, undefined} ->
            ok;
        {R, Rst} ->
            RemVal = binary_to_integer(R),
            RstVal = binary_to_integer(binary:part(Rst, 0, min(byte_size(Rst), 10))),
            ets:insert(?TAB, {Key, RemVal, RstVal})
    end,
    NewState = maps:update_with(global_count, fun(C) -> C + 1 end, State),
    {noreply, NewState};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(reset_global, _State) ->
    schedule_global_reset(),
    {noreply, #{global_count => 0}};
handle_info(_Info, State) ->
    {noreply, State}.

%% Internal

check_global(Now) ->
    case ets:lookup(?TAB, ?GLOBAL_KEY) of
        [{?GLOBAL_KEY, Count, Reset}] when Count >= ?GLOBAL_LIMIT, Reset > Now ->
            {wait, (Reset - Now) * 1000};
        _ ->
            ok
    end.

schedule_global_reset() ->
    erlang:send_after(1000, self(), reset_global).

bucket_key(Method, Route) ->
    <<Method/binary, ":", (normalize_route(Route))/binary>>.

%% Discord scopes rate limits per route template, keyed by the major parameter
%% (channel, guild or webhook id); bucketing on the raw path matches no limit
%% the API actually reports back.
normalize_route(Route) ->
    [Path | _Query] = binary:split(Route, ~"?"),
    Segments = [Segment || Segment <- binary:split(Path, ~"/", [global]), Segment =/= <<>>],
    iolist_to_binary([[~"/", Segment] || Segment <- template(Segments)]).

template([~"channels", Id | Rest]) ->
    [~"channels", major(Id) | placeholders(Rest)];
template([~"guilds", Id | Rest]) ->
    [~"guilds", major(Id) | placeholders(Rest)];
template([~"applications", Id, ~"guilds", GuildId | Rest]) ->
    [~"applications", major(Id), ~"guilds", major(GuildId) | placeholders(Rest)];
template([~"webhooks", Id, _Token | Rest]) ->
    [~"webhooks", major(Id), ~":token" | placeholders(Rest)];
template([~"interactions", _Id, _Token | Rest]) ->
    [~"interactions", ~":id", ~":token" | placeholders(Rest)];
template(Segments) ->
    placeholders(Segments).

%% A major parameter is only kept verbatim when it is a real snowflake, so a
%% malformed id cannot mint a permanent ETS key of attacker-chosen size.
major(Id) ->
    case is_snowflake(Id) of
        true -> Id;
        false -> ~":id"
    end.

placeholders(Segments) ->
    [placeholder(Segment) || Segment <- Segments].

placeholder(Segment) ->
    case is_snowflake(Segment) of
        true -> ~":id";
        false -> Segment
    end.

is_snowflake(<<>>) -> false;
is_snowflake(Segment) -> is_all_digits(Segment).

is_all_digits(<<>>) -> true;
is_all_digits(<<Digit, Rest/binary>>) when Digit >= $0, Digit =< $9 -> is_all_digits(Rest);
is_all_digits(_) -> false.

find_header(Name, Headers) ->
    case lists:keyfind(Name, 1, Headers) of
        {Name, Value} ->
            Value;
        false ->
            LowerName = string:lowercase(Name),
            case lists:keyfind(LowerName, 1, Headers) of
                {LowerName, Value} -> Value;
                false -> undefined
            end
    end.
