-module(denshi_heartbeat).
-behaviour(gen_server).

-export([start_link/0, start_beating/2, stop_beating/0, ack/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(state, {
    gateway_pid :: pid() | undefined,
    interval :: non_neg_integer() | undefined,
    timer_ref :: reference() | undefined,
    ack_received = true :: boolean(),
    missed = 0 :: non_neg_integer()
}).

-spec start_link() -> gen_server:start_ret().
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec start_beating(pid(), non_neg_integer()) -> ok.
start_beating(GatewayPid, Interval) ->
    gen_server:cast(?MODULE, {start, GatewayPid, Interval}).

-spec stop_beating() -> ok.
stop_beating() ->
    gen_server:cast(?MODULE, stop).

-spec ack() -> ok.
ack() ->
    gen_server:cast(?MODULE, ack).

%% gen_server callbacks

init([]) ->
    {ok, #state{}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({start, GatewayPid, Interval}, State) ->
    cancel_timer(State),
    Jitter = rand:uniform(Interval),
    TimerRef = erlang:send_after(Jitter, self(), heartbeat),
    {noreply, State#state{
        gateway_pid = GatewayPid,
        interval = Interval,
        timer_ref = TimerRef,
        ack_received = true,
        missed = 0
    }};
handle_cast(stop, State) ->
    cancel_timer(State),
    {noreply, State#state{
        timer_ref = undefined,
        gateway_pid = undefined,
        interval = undefined
    }};
handle_cast(ack, State) ->
    {noreply, State#state{ack_received = true, missed = 0}};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(heartbeat, #state{ack_received = false, missed = Missed} = State) when
    Missed >= 2
->
    logger:warning(~"Discord heartbeat: missed ~B ACKs, requesting reconnect", [Missed + 1]),
    State#state.gateway_pid ! zombie_connection,
    cancel_timer(State),
    {noreply, State#state{timer_ref = undefined}};
handle_info(heartbeat, #state{ack_received = false, missed = Missed} = State) ->
    logger:debug(~"Discord heartbeat: missed ACK (~B), retrying", [Missed + 1]),
    State#state.gateway_pid ! send_heartbeat,
    TimerRef = erlang:send_after(State#state.interval, self(), heartbeat),
    {noreply, State#state{timer_ref = TimerRef, missed = Missed + 1}};
handle_info(heartbeat, #state{gateway_pid = GatewayPid, interval = Interval} = State) ->
    GatewayPid ! send_heartbeat,
    TimerRef = erlang:send_after(Interval, self(), heartbeat),
    {noreply, State#state{timer_ref = TimerRef, ack_received = false}};
handle_info(_Info, State) ->
    {noreply, State}.

%% Internal

cancel_timer(#state{timer_ref = undefined}) ->
    ok;
cancel_timer(#state{timer_ref = Ref}) ->
    _ = erlang:cancel_timer(Ref),
    ok.
