-module(denshi_interaction).

-export([
    parse/1,
    pong/0,
    message/1,
    deferred_message/0,
    deferred_message/1,
    update_message/1,
    modal/2
]).

-include("denshi.hrl").

-spec parse(map()) -> #denshi_interaction{}.
parse(Data) ->
    #denshi_interaction{
        id = maps:get(~"id", Data),
        application_id = maps:get(~"application_id", Data),
        type = maps:get(~"type", Data),
        data = maps:get(~"data", Data, undefined),
        guild_id = maps:get(~"guild_id", Data, undefined),
        channel_id = maps:get(~"channel_id", Data, undefined),
        member = maps:get(~"member", Data, undefined),
        user = maps:get(~"user", Data, undefined),
        token = maps:get(~"token", Data),
        version = maps:get(~"version", Data, 1)
    }.

-spec pong() -> map().
pong() ->
    #{~"type" => 1}.

-spec message(map()) -> map().
message(Data) ->
    #{~"type" => 4, ~"data" => Data}.

-spec deferred_message() -> map().
deferred_message() ->
    #{~"type" => 5}.

-spec deferred_message(map()) -> map().
deferred_message(Data) ->
    #{~"type" => 5, ~"data" => Data}.

-spec update_message(map()) -> map().
update_message(Data) ->
    #{~"type" => 7, ~"data" => Data}.

-spec modal(binary(), map()) -> map().
modal(CustomId, ModalData) ->
    #{~"type" => 9, ~"data" => ModalData#{~"custom_id" => CustomId}}.
