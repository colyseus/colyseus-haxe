package io.colyseus;

enum abstract Protocol(Int) to Int {
    // User-related (0~9)
    var USER_ID = 1;

    // Room-related (9~19)
    var JOIN_REQUEST = 9;
    var JOIN_ROOM = 10;
    var ERROR = 11;
    var LEAVE_ROOM = 12;
    var ROOM_DATA = 13;
    var ROOM_STATE = 14;
    var ROOM_STATE_PATCH = 15;

    // var ROOM_DATA_SCHEMA = 16;
    var ROOM_DATA_BYTES = 17;

    // Match-making related (20~29)
    var ROOM_LIST = 20;

    // Generic messages (50~60)
    var BAD_REQUEST = 50;

    // devMode close code
    var DEVMODE_RESTART = 4010;
}
