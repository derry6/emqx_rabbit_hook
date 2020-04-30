%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

%%
%% Modified from emqx_web_hook
%% Derry6.

-module(emqx_rabbit_hook).

-include("emqx_rabbit_hook.hrl").
-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/logger.hrl").

-logger_header("[RabbitHook]").

%% APIs
-export([load/0, register_metrics/0, unload/0]).
%% Hooks callback
-export([on_client_connack/4, on_client_connect/3]).
-export([on_client_connected/3, on_client_disconnected/4]).
-export([on_client_subscribe/4, on_client_unsubscribe/4]).
-export([on_session_subscribed/4, on_session_terminated/4, on_session_unsubscribed/4]).
-export([on_message_acked/3, on_message_delivered/3, on_message_publish/2]).
-export([amqp_pub/2]).

%%--------------------------------------------------------------------
%% APIs
%%--------------------------------------------------------------------

register_metrics() ->
    Metrics = [
        'rabbit_hook.client_connect',
        'rabbit_hook.client_connack',
        'rabbit_hook.client_connected',
        'rabbit_hook.client_disconnected',
        'rabbit_hook.client_subscribe',
        'rabbit_hook.client_unsubscribe',
        'rabbit_hook.session_subscribed',
        'rabbit_hook.session_unsubscribed',
        'rabbit_hook.session_terminated',
        'rabbit_hook.message_publish',
        'rabbit_hook.message_delivered',
        'rabbit_hook.message_acked'
    ],
    lists:foreach(fun emqx_metrics:new/1, Metrics).

% Application started
load() ->
    lists:foreach(
        fun({Hook, Env}) ->
            #{type := Type, exchange := Exchange} = Env,
%%           todo: ignore duplicated exchange
            emqx_rabbit_hook_cli:ensure_exchange(Type, Exchange),
            load_(Hook, Env)
        end,
        emqx_rabbit_hook_env:hook_rules()
    ).

unload() ->
    ?LOG(info, "AMQP plugin unloaded"),
    lists:foreach(
        fun({Hook, _Type, _Exchange, _Routing}) ->
            unload_(Hook)
        end,
        emqx_rabbit_hook_env:hook_rules()
    ).

%%--------------------------------------------------------------------
%% Client connect
%%--------------------------------------------------------------------

on_client_connect(ConnInfo = #{clientid := ClientId, username := Username, peername := {Peerhost, _}}, _ConnProp, Env) ->
    emqx_metrics:inc('rabbit_hook.client_connect'),
    Params = #{
        action => client_connect,
        clientid => ClientId,
        username => maybe(Username),
        ipaddress => iolist_to_binary(ntoa(Peerhost)),
        keepalive => maps:get(keepalive, ConnInfo),
        proto_ver => maps:get(proto_ver, ConnInfo)
    },
    amqp_pub(Env, Params),
    ok;
on_client_connect(#{}, _ConnProp, _Env) -> ok.

%%--------------------------------------------------------------------
%% Client connack
%%--------------------------------------------------------------------

on_client_connack(ConnInfo = #{clientid := ClientId, username := Username, peername := {Peerhost, _}}, Rc, _AckProp, Env) ->
    emqx_metrics:inc('rabbit_hook.client_connack'),
    Params = #{
        action => client_connack,
        clientid => ClientId, username => maybe(Username),
        ipaddress => iolist_to_binary(ntoa(Peerhost)),
        keepalive => maps:get(keepalive, ConnInfo),
        proto_ver => maps:get(proto_ver, ConnInfo),
        conn_ack => Rc
    },
    amqp_pub(Env, Params),
    ok;
on_client_connack(#{}, _Rc, _AckProp, _Env) -> ok.

%%--------------------------------------------------------------------
%% Client connected
%%--------------------------------------------------------------------

on_client_connected(#{clientid := ClientId, username := Username, peerhost := Peerhost}, ConnInfo, Env) ->
    emqx_metrics:inc('rabbit_hook.client_connected'),
    Params = #{action => client_connected,
        clientid => ClientId,
        username => maybe(Username),
        ipaddress => iolist_to_binary(ntoa(Peerhost)),
        keepalive => maps:get(keepalive, ConnInfo),
        proto_ver => maps:get(proto_ver, ConnInfo),
        connected_at => maps:get(connected_at, ConnInfo)
    },
    amqp_pub(Env, Params),
    ok;
on_client_connected(#{}, _ConnInfo, _Env) -> ok.

%%--------------------------------------------------------------------
%% Client disconnected
%%--------------------------------------------------------------------

on_client_disconnected(ClientInfo, {shutdown, Reason}, ConnInfo, Env) when is_atom(Reason) ->
    on_client_disconnected(ClientInfo, Reason, ConnInfo, Env);
on_client_disconnected(#{clientid := ClientId, username := Username}, Reason, _ConnInfo, Env) ->
    emqx_metrics:inc('rabbit_hook.client_disconnected'),
    Params = #{action => client_disconnected,
        clientid => ClientId,
        username => maybe(Username),
        reason => stringfy(Reason)
    },
    amqp_pub(Env, Params),
    ok.

%%--------------------------------------------------------------------
%% Client subscribe
%%--------------------------------------------------------------------

on_client_subscribe(#{clientid := ClientId, username := Username}, _Properties, TopicTable, Env) ->
    #{filter := Filter} = Env,
    lists:foreach(
        fun({Topic, Opts}) ->
            with_filter(
                fun() ->
                    emqx_metrics:inc('rabbit_hook.client_subscribe'),
                    Params = #{
                        action => client_subscribe,
                        clientid => ClientId,
                        username => maybe(Username),
                        topic => Topic,
                        opts => Opts
                    },
                    amqp_pub(Env, Params)
                end,
                Topic, Filter)
        end,
        TopicTable).

%%--------------------------------------------------------------------
%% Client unsubscribe
%%--------------------------------------------------------------------

on_client_unsubscribe(#{clientid := ClientId, username := Username}, _Properties, TopicTable, Env) ->
    #{filter := Filter} = Env,
    lists:foreach(
        fun({Topic, Opts}) ->
            with_filter(
                fun() ->
                    emqx_metrics:inc('rabbit_hook.client_unsubscribe'),
                    Params = #{
                        action => client_unsubscribe,
                        clientid => ClientId,
                        username => maybe(Username),
                        topic => Topic,
                        opts => Opts
                    },
                    amqp_pub(Env, Params)
                end,
                Topic, Filter)
        end,
        TopicTable).

%%--------------------------------------------------------------------
%% Session subscribed
%%--------------------------------------------------------------------

on_session_subscribed(#{clientid := ClientId, username := Username}, Topic, Opts, Env) ->
    #{filter := Filter} = Env,
    with_filter(
        fun() ->
            emqx_metrics:inc('rabbit_hook.session_subscribed'),
            Params = #{action => session_subscribed,
                clientid => ClientId,
                username => maybe(Username),
                topic => Topic,
                opts => Opts
            },
            amqp_pub(Env, Params)
        end,
        Topic, Filter).

%%--------------------------------------------------------------------
%% Session unsubscribed
%%--------------------------------------------------------------------

on_session_unsubscribed(#{clientid := ClientId, username := Username}, Topic, _Opts, Env) ->
    #{filter := Filter} = Env,
    with_filter(
        fun() ->
            emqx_metrics:inc('rabbit_hook.session_unsubscribed'),
            Params = #{action => session_unsubscribed,
                clientid => ClientId,
                username => maybe(Username),
                topic => Topic
            },
            amqp_pub(Env, Params)
        end,
        Topic, Filter).

%%--------------------------------------------------------------------
%% Session terminated
%%--------------------------------------------------------------------

on_session_terminated(Info, {shutdown, Reason}, SessInfo, Env) when is_atom(Reason) ->
    on_session_terminated(Info, Reason, SessInfo, Env);

on_session_terminated(#{clientid := ClientId, username := Username}, Reason, _SessInfo, Env) when is_atom(Reason) ->
    emqx_metrics:inc('rabbit_hook.session_terminated'),
    Params = #{action => session_terminated,
        clientid => ClientId,
        username => maybe(Username),
        reason => Reason
    },
    amqp_pub(Env, Params),
    ok;
on_session_terminated(#{}, Reason, _SessInfo, _Env) ->
    ?LOG(error, "Session terminated, cannot encode the " "reason: ~p", [Reason]),
    ok.

%%--------------------------------------------------------------------
%% Message publish
%%--------------------------------------------------------------------

on_message_publish(Message = #message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};

on_message_publish(Message = #message{topic = Topic, flags = #{retain := Retain}}, Env) ->
    #{filter := Filter} = Env,
    with_filter(
        fun() ->
            emqx_metrics:inc('rabbit_hook.message_publish'),
            {FromClientId, FromUsername} = format_from(Message),
            Params = #{action => message_publish,
                from_client_id => FromClientId,
                from_username => maybe(FromUsername),
                topic => Message#message.topic,
                qos => Message#message.qos, retain => Retain,
                payload => encode_payload(Message#message.payload),
                ts => Message#message.timestamp
            },
            amqp_pub(Env, Params),
            {ok, Message}
        end,
        Message, Topic, Filter).

%%--------------------------------------------------------------------
%% Message deliver
%%--------------------------------------------------------------------

on_message_delivered(#{clientid := ClientId, username := Username}, Message = #message{topic = Topic, flags = #{retain := Retain}}, Env) ->
    #{filter := Filter} = Env,
    with_filter(
        fun() ->
            emqx_metrics:inc('rabbit_hook.message_delivered'),
            {FromClientId, FromUsername} = format_from(Message),
            Params = #{action => message_delivered,
                clientid => ClientId, username => Username,
                from_client_id => FromClientId,
                from_username => maybe(FromUsername),
                topic => Message#message.topic,
                qos => Message#message.qos, retain => Retain,
                payload => encode_payload(Message#message.payload),
                ts => Message#message.timestamp
            },
            amqp_pub(Env, Params)
        end,
        Topic, Filter).

%%--------------------------------------------------------------------
%% Message acked
%%--------------------------------------------------------------------
on_message_acked(#{clientid := ClientId}, Message = #message{topic = Topic, flags = #{retain := Retain}}, Env) ->
    #{filter := Filter} = Env,
    with_filter(
        fun() ->
            emqx_metrics:inc('rabbit_hook.message_acked'),
            {FromClientId, FromUsername} = format_from(Message),
            Params = #{action => message_acked,
                clientid => ClientId,
                from_client_id => FromClientId,
                from_username => maybe(FromUsername),
                topic => Message#message.topic,
                qos => Message#message.qos, retain => Retain,
                payload => encode_payload(Message#message.payload),
                ts => Message#message.timestamp
            },
            amqp_pub(Env, Params)
        end,
        Topic, Filter).

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------
amqp_pub(_Env = #{exchange := Exchange, routing := Routing}, Params) ->
    case application:get_env(?APP, payload_encoding, json) of
        bson ->
            emqx_rabbit_hook_cli:pub(Exchange, Routing, bson_binary:put_document(Params));
        _ ->
            emqx_rabbit_hook_cli:pub(Exchange, Routing, emqx_json:encode(Params))
    end.

with_filter(Fun, _, undefined) -> Fun(), ok;
with_filter(Fun, Topic, Filter) ->
    case emqx_topic:match(Topic, Filter) of
        true -> Fun(), ok;
        false -> ok
    end.

with_filter(Fun, _, _, undefined) -> Fun();
with_filter(Fun, Msg, Topic, Filter) ->
    case emqx_topic:match(Topic, Filter) of
        true -> Fun();
        false -> {ok, Msg}
    end.

%% add hooks
load_(Hook, Params) ->
    case Hook of
        'client.connect' -> emqx:hook(Hook, {?MODULE, on_client_connect, [Params]});
        'client.connack' -> emqx:hook(Hook, {?MODULE, on_client_connack, [Params]});
        'client.connected' -> emqx:hook(Hook, {?MODULE, on_client_connected, [Params]});
        'client.disconnected' -> emqx:hook(Hook, {?MODULE, on_client_disconnected, [Params]});
        'client.subscribe' -> emqx:hook(Hook, {?MODULE, on_client_subscribe, [Params]});
        'client.unsubscribe' -> emqx:hook(Hook, {?MODULE, on_client_unsubscribe, [Params]});
        'session.subscribed' -> emqx:hook(Hook, {?MODULE, on_session_subscribed, [Params]});
        'session.unsubscribed' -> emqx:hook(Hook, {?MODULE, on_session_unsubscribed, [Params]});
        'session.terminated' -> emqx:hook(Hook, {?MODULE, on_session_terminated, [Params]});
        'message.publish' -> emqx:hook(Hook, {?MODULE, on_message_publish, [Params]});
        'message.acked' -> emqx:hook(Hook, {?MODULE, on_message_acked, [Params]});
        'message.delivered' -> emqx:hook(Hook, {?MODULE, on_message_delivered, [Params]})
    end.

unload_(Hook) ->
    case Hook of
        'client.connect' -> emqx:unhook(Hook, {?MODULE, on_client_connect});
        'client.connack' -> emqx:unhook(Hook, {?MODULE, on_client_connack});
        'client.connected' -> emqx:unhook(Hook, {?MODULE, on_client_connected});
        'client.disconnected' -> emqx:unhook(Hook, {?MODULE, on_client_disconnected});
        'client.subscribe' -> emqx:unhook(Hook, {?MODULE, on_client_subscribe});
        'client.unsubscribe' -> emqx:unhook(Hook, {?MODULE, on_client_unsubscribe});
        'session.subscribed' -> emqx:unhook(Hook, {?MODULE, on_session_subscribed});
        'session.unsubscribed' -> emqx:unhook(Hook, {?MODULE, on_session_unsubscribed});
        'session.terminated' -> emqx:unhook(Hook, {?MODULE, on_session_terminated});
        'message.publish' -> emqx:unhook(Hook, {?MODULE, on_message_publish});
        'message.acked' -> emqx:unhook(Hook, {?MODULE, on_message_acked});
        'message.delivered' -> emqx:unhook(Hook, {?MODULE, on_message_delivered})
    end.


%% ============= Utils ==============

format_from(#message{from = ClientId, headers = #{username := Username}}) -> {a2b(ClientId), a2b(Username)};
format_from(#message{from = ClientId, headers = _HeadersNoUsername}) -> {a2b(ClientId), <<"undefined">>}.

encode_payload(Payload) -> encode_payload(Payload, emqx_rabbit_hook_env:payload_encoding()).
encode_payload(Payload, base62) -> emqx_base62:encode(Payload);
encode_payload(Payload, base64) -> base64:encode(Payload);
encode_payload(Payload, _) -> Payload.

a2b(A) when is_atom(A) -> erlang:atom_to_binary(A, utf8);
a2b(A) -> A.

ntoa({0, 0, 0, 0, 0, 65535, AB, CD}) -> inet_parse:ntoa({AB bsr 8, AB rem 256, CD bsr 8, CD rem 256});
ntoa(IP) -> inet_parse:ntoa(IP).

stringfy(undefined) -> null;
stringfy(Term) when is_atom(Term); is_binary(Term) -> Term;
stringfy(Term) -> iolist_to_binary(io_lib:format("~0p", [Term])).

maybe(undefined) -> null;
maybe(Str) -> Str.
