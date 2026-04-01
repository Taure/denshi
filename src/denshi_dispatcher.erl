-module(denshi_dispatcher).
-behaviour(gen_server).

-export([start_link/1, dispatch/2, register_consumer/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(state, {
    consumers = #{} :: #{atom() => [{module(), term()}]}
}).

-spec start_link([module()]) -> gen_server:start_ret().
start_link(Consumers) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Consumers, []).

-spec dispatch(atom(), map()) -> ok.
dispatch(EventName, Data) ->
    gen_server:cast(?MODULE, {dispatch, EventName, Data}).

-spec register_consumer(module()) -> ok.
register_consumer(Module) ->
    gen_server:call(?MODULE, {register, Module}).

%% gen_server callbacks

init(Consumers) ->
    State = lists:foldl(fun add_consumer/2, #state{}, Consumers),
    {ok, State}.

handle_call({register, Module}, _From, State) ->
    NewState = add_consumer(Module, State),
    {reply, ok, NewState};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({dispatch, EventName, Data}, State) ->
    Consumers = State#state.consumers,
    case maps:get(EventName, Consumers, []) of
        [] ->
            {noreply, State};
        EventConsumers ->
            NewConsumers = dispatch_to_consumers(EventName, Data, EventConsumers, []),
            {noreply, State#state{
                consumers = maps:put(EventName, NewConsumers, Consumers)
            }}
    end;
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

%% Internal

add_consumer(Module, #state{consumers = Consumers} = State) ->
    ConsumerState =
        case erlang:function_exported(Module, init, 0) of
            true ->
                {ok, S} = Module:init(),
                S;
            false ->
                #{}
        end,
    Events = Module:events(),
    NewConsumers = lists:foldl(
        fun(Event, Acc) ->
            Existing = maps:get(Event, Acc, []),
            maps:put(Event, Existing ++ [{Module, ConsumerState}], Acc)
        end,
        Consumers,
        Events
    ),
    State#state{consumers = NewConsumers}.

dispatch_to_consumers(_EventName, _Data, [], Acc) ->
    lists:reverse(Acc);
dispatch_to_consumers(EventName, Data, [{Module, ConsumerState} | Rest], Acc) ->
    try Module:handle_event(EventName, Data, ConsumerState) of
        {ok, NewState} ->
            dispatch_to_consumers(EventName, Data, Rest, [{Module, NewState} | Acc])
    catch
        Class:Reason:Stacktrace ->
            logger:error(
                ~"Consumer ~s crashed handling ~s: ~p:~p~n~p",
                [Module, EventName, Class, Reason, Stacktrace]
            ),
            dispatch_to_consumers(EventName, Data, Rest, [{Module, ConsumerState} | Acc])
    end.
