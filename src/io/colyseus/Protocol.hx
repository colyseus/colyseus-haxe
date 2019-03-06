package io.colyseus;

class Protocol {
    // User-related (0~9)
    public static var USER_ID = 1;

    // Room-related (9~19)
    public static var JOIN_REQUEST = 9;
    public static var JOIN_ROOM = 10;
    public static var JOIN_ERROR = 11;
    public static var LEAVE_ROOM = 12;
    public static var ROOM_DATA = 13;
    public static var ROOM_STATE = 14;
    public static var ROOM_STATE_PATCH = 15;

    // Match-making related (20~29)
    public static var ROOM_LIST = 20;

    // Generic messages (50~60)
    public static var BAD_REQUEST = 50;
}
