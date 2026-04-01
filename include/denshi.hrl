-ifndef(DENSHI_HRL).
-define(DENSHI_HRL, true).

%% Gateway event envelope
-record(denshi_event, {
    op :: non_neg_integer(),
    name :: atom() | undefined,
    data :: term(),
    sequence :: non_neg_integer() | undefined
}).

%% Gateway session state (internal)
-record(denshi_session, {
    token :: binary(),
    intents :: non_neg_integer(),
    session_id :: binary() | undefined,
    resume_url :: binary() | undefined,
    sequence :: non_neg_integer() | undefined
}).

%% Parsed interaction
-record(denshi_interaction, {
    id :: binary(),
    application_id :: binary(),
    type :: non_neg_integer(),
    data :: map() | undefined,
    guild_id :: binary() | undefined,
    channel_id :: binary() | undefined,
    member :: map() | undefined,
    user :: map() | undefined,
    token :: binary(),
    version :: non_neg_integer()
}).

-endif.
