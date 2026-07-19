# denshi

[![CI](https://github.com/Taure/denshi/actions/workflows/ci.yml/badge.svg)](https://github.com/Taure/denshi/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/denshi.svg)](https://hex.pm/packages/denshi)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/denshi)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Discord API client for Erlang/OTP. Gateway websocket with automatic reconnect and resume, REST client with rate-limit handling, and a consumer behaviour for handling events.

## Installation

```erlang
{deps, [{denshi, "~> 0.1"}]}.
```

## Configuration

```erlang
[{denshi, [
    {token, <<"YOUR_BOT_TOKEN">>},
    {intents, [guilds, guild_messages, message_content]},
    {consumers, [my_bot_consumer]}
]}].
```

Intents are given as atoms and combined into the gateway bitfield. `message_content` is privileged and must also be enabled in the Discord developer portal.

## Consumers

```erlang
-module(my_bot_consumer).
-behaviour(denshi_consumer).

-export([events/0, handle_event/3]).

events() ->
    [thread_create].

handle_event(thread_create, _Thread, State) ->
    {ok, State}.
```

`init/0` is optional and seeds the state threaded through `handle_event/3`.

## REST

| Function | Endpoint |
| --- | --- |
| `get_gateway_bot/1` | `GET /gateway/bot` |
| `send_message/3` | `POST /channels/:id/messages` |
| `get_channel_messages/3` | `GET /channels/:id/messages` |
| `get_message/3` | `GET /channels/:id/messages/:id` |
| `delete_message/3` | `DELETE /channels/:id/messages/:id` |
| `get_channel/2` | `GET /channels/:id` |
| `get_guild/2` | `GET /guilds/:id` |
| `create_global_command/3` | `POST /applications/:id/commands` |
| `create_guild_command/4` | `POST /applications/:id/guilds/:id/commands` |
| `create_interaction_response/4` | `POST /interactions/:id/:token/callback` |
| `edit_original_response/4` | `PATCH /webhooks/:id/:token/messages/@original` |

Rate limits are tracked per route template keyed by the major parameter, matching how Discord scopes its buckets.

## License

MIT
