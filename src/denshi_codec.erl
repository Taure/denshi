-module(denshi_codec).

-export([encode/1, decode/1, decode_list/1, gateway_frame/2, gateway_frame/3]).

-include("denshi.hrl").

-spec encode(term()) -> binary().
encode(Term) ->
    iolist_to_binary(json:encode(Term)).

-spec decode(binary()) -> map().
decode(Bin) ->
    json:decode(Bin).

-doc """
Decode a JSON array of objects.

Most Discord endpoints return an object, but the message-history endpoints
return a bare array. Unexpected elements are an error rather than being
filtered out, so a short list always means a short response and callers can
paginate on length without silently losing messages.
""".
-spec decode_list(binary()) -> {ok, [map()]} | {error, not_a_list | not_a_list_of_objects}.
decode_list(Bin) ->
    case json:decode(Bin) of
        Items when is_list(Items) -> objects(Items, []);
        _ -> {error, not_a_list}
    end.

objects([], Acc) ->
    {ok, lists:reverse(Acc)};
objects([Item | Rest], Acc) when is_map(Item) ->
    objects(Rest, [Item | Acc]);
objects(_Items, _Acc) ->
    {error, not_a_list_of_objects}.

-spec gateway_frame(non_neg_integer(), term()) -> binary().
gateway_frame(Op, Data) ->
    encode(#{~"op" => Op, ~"d" => Data}).

-spec gateway_frame(non_neg_integer(), term(), non_neg_integer() | undefined) -> binary().
gateway_frame(Op, Data, undefined) ->
    gateway_frame(Op, Data);
gateway_frame(Op, Data, Sequence) ->
    encode(#{~"op" => Op, ~"d" => Data, ~"s" => Sequence}).
