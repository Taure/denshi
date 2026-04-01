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
    _ = ets:new(?TAB, [named_table, public, set, {read_concurrency, true}]),
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
    <<Method/binary, ":", Route/binary>>.

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
