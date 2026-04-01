-module(denshi_consumer).

-callback init() -> {ok, State :: term()}.
-callback events() -> [atom()].
-callback handle_event(Event :: atom(), Data :: map(), State :: term()) ->
    {ok, NewState :: term()}.

-optional_callbacks([init/0]).
