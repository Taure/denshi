-module(denshi_sup).
-behaviour(supervisor).

-export([start_link/1]).
-export([init/1]).

-spec start_link(map()) -> supervisor:startlink_ret().
start_link(Config) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, Config).

init(Config) ->
    Consumers = maps:get(consumers, Config, []),
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },
    Children = [
        #{
            id => denshi_ratelimit,
            start => {denshi_ratelimit, start_link, []},
            restart => permanent,
            type => worker
        },
        #{
            id => denshi_dispatcher,
            start => {denshi_dispatcher, start_link, [Consumers]},
            restart => permanent,
            type => worker
        },
        #{
            id => denshi_gateway_sup,
            start => {denshi_gateway_sup, start_link, [Config]},
            restart => permanent,
            type => supervisor
        }
    ],
    {ok, {SupFlags, Children}}.
