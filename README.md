
emqx_rabbit_hook
=============

EMQ X 的 RabbitMQ 插件，消息转发到RabbitMQ.

##### emqx_rabbit_hook.conf

```properties
# RabbitMQ broker 配置
hook.rabbit.host = １27.0.0.1
hook.rabbit.port = 5672
hook.rabbit.virtual_host = /
hook.rabbit.username = learn_emqx
hook.rabbit.password = learn_emqx
hook.rabbit.heartbeat = 10
hook.rabbit.auto_reconnect = 1
# hook.rabbit.ssl_opts = ""
hook.rabbit.pool_size = 10

＃　转发规则配置
# type: RabbitMQ 交换机类型
# exchange: RabbitMQ 交换机名称
# routing: RabbitMQ　路由Key
# topic: EMQX topic过滤器，指定那些topic的消息转发到RabbitMQ

hook.rabbit.rule.client.connect.1       = {"type": "topic", "exchange" : "emqx.client.events"}
hook.rabbit.rule.client.connack.1       = {"type": "topic", "exchange" : "emqx.client.events"}
hook.rabbit.rule.client.connected.1     = {"type": "topic", "exchange" : "emqx.client.events"}
hook.rabbit.rule.client.disconnected.1  = {"type": "topic", "exchange" : "emqx.client.events"}
hook.rabbit.rule.client.subscribe.1     = {"type": "topic", "exchange" : "emqx.client.events"}
hook.rabbit.rule.client.unsubscribe.1   = {"type": "topic", "exchange" : "emqx.client.events"}
hook.rabbit.rule.session.subscribed.1   = {"type": "topic", "exchange" : "emqx.client.events"}
hook.rabbit.rule.session.unsubscribed.1 = {"type": "topic", "exchange" : "emqx.client.events"}
hook.rabbit.rule.session.terminated.1   = {"type": "topic", "exchange" : "emqx.client.events"}
hook.rabbit.rule.message.publish.1      = {"type": "topic", "exchange" : "emqx.client.events"}
hook.rabbit.rule.message.delivered.1    = {"type": "topic", "exchange" : "emqx.client.events"}
hook.rabbit.rule.message.acked.1        = {"type": "topic", "exchange" : "emqx.client.events"}

```

API
----
* client.connected
```json
{
    "action":"client_connected",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "keepalive": 60,
    "ipaddress": "127.0.0.1",
    "proto_ver": 4,
    "connected_at": 1556176748,
    "conn_ack":0
}
```

* client.disconnected
```json
{
    "action":"client_disconnected",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "reason":"normal"
}
```

* client.subscribe
```json
{
    "action":"client_subscribe",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "topic":"world",
    "opts":{
        "qos":0
    }
}
```

* client.unsubscribe
```json
{
    "action":"client_unsubscribe",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "topic":"world"
}
```

* session.created
```json
{
    "action":"session_created",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117"
}
```

* session.subscribed
```json
{
    "action":"session_subscribed",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "topic":"world",
    "opts":{
        "qos":0
    }
}
```

* session.unsubscribed
```json
{
    "action":"session_unsubscribed",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "topic":"world"
}
```

* session.terminated
```json
{
    "action":"session_terminated",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "reason":"normal"
}
```

* message.publish
```json
{
    "action":"message_publish",
    "from_client_id":"C_1492410235117",
    "from_username":"C_1492410235117",
    "topic":"world",
    "qos":0,
    "retain":true,
    "payload":"Hello world!",
    "ts":1492412774
}
```

* message.deliver
```json
{
    "action":"message_delivered",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "from_client_id":"C_1492410235117",
    "from_username":"C_1492410235117",
    "topic":"world",
    "qos":0,
    "retain":true,
    "payload":"Hello world!",
    "ts":1492412826
}
```

* message.acked

```json
{
    "action":"message_acked",
    "clientid":"C_1492410235117",
    "username":"C_1492410235117",
    "from_client_id":"C_1492410235117",
    "from_username":"C_1492410235117",
    "topic":"world",
    "qos":1,
    "retain":true,
    "payload":"Hello world!",
    "ts":1492412914
}
```


参考
-------
修改自[emqx_web_hook](https://github.com/emqx/emqx-web-hook).

License
-------

Apache License Version 2.0