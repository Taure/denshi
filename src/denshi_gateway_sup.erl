-module(denshi_gateway_sup).
-behaviour(supervisor).

-export([start_link/1]).
-export([init/1]).

-spec start_link(map()) -> supervisor:startlink_ret().
start_link(Config) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, Config).

init(Config) ->
    SupFlags = #{
        strategy => rest_for_one,
        intensity => 5,
        period => 10
    },
    Children = [
        #{
            id => denshi_gateway,
            start => {denshi_gateway, start_link, [Config]},
            restart => permanent,
            type => worker
        },
        #{
            id => denshi_heartbeat,
            start => {denshi_heartbeat, start_link, []},
            restart => permanent,
            type => worker
        }
    ],
    {ok, {SupFlags, Children}}.
