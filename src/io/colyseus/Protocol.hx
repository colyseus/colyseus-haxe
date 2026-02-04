package io.colyseus;

enum abstract Protocol(Int) to Int {
    // Room-related (9~19)
    var JOIN_ROOM = 10;
    var ERROR = 11;
    var LEAVE_ROOM = 12;
    var ROOM_DATA = 13;
    var ROOM_STATE = 14;
    var ROOM_STATE_PATCH = 15;
    // var ROOM_DATA_SCHEMA = 16;
    var ROOM_DATA_BYTES = 17;
    var PING = 18;
}

enum abstract CloseCode(Int) to Int {
    var NORMAL_CLOSURE = 1000;
    var GOING_AWAY = 1001;
    var NO_STATUS_RECEIVED = 1005;
    var ABNORMAL_CLOSURE = 1006;

    var CONSENTED = 4000;
    var SERVER_SHUTDOWN = 4001;
    var WITH_ERROR = 4002;
    var MAY_TRY_RECONNECT = 4010;
}