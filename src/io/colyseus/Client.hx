package io.colyseus;

import haxe.io.Bytes;

interface RoomAvailable {
    roomId: String;
    clients: Int;
    maxClients: Int;
    metadata: Dynamic;
}

class Client {
    public id: String;

    // callbacks
    public dynamic function onOpen():Void {}
    public dynamic function onMessage():Void {}
    public dynamic function onClose():Void {}
    public dynamic function onError():Void {}

    private connection: Connection;

    private rooms: Map<String, Room> = [];
    private connectingRooms: Map<String, Room> = {};
    private requestId = 0;

    private hostname: String;
    private roomsAvailableRequests: {[requestId: number]: (value?: RoomAvailable[]) => void} = {};

    public function new (url: String) {
        this.hostname = url;
        getItem('colyseusid', (colyseusid) => this.connect(colyseusid));
    }

    public join(roomName: String, options: Dynamic = {}): Room {
        options.requestId = ++this.requestId;

        var room = new Room(roomName, options);

        // remove references on leaving
        room.onLeave = function () {
            this.rooms.remove(room.id);
            this.connectingRooms.remove(options.requestId);
        });

        this.connectingRooms.set(options.requestId, room);

        this.connection.send([Protocol.JOIN_ROOM, roomName, options]);

        return room;
    }

    public rejoin<T>(roomName: string, sessionId: string) {
        return this.join(roomName, { sessionId });
    }

    public getAvailableRooms(roomName: String, callback: (rooms: RoomAvailable[], err?: string) => void) {
        // reject this promise after 10 seconds.
        const requestId = ++this.requestId;
        const removeRequest = () => delete this.roomsAvailableRequests[requestId];
        const rejectionTimeout = setTimeout(() => {
            removeRequest();
            callback([], 'timeout');
        }, 10000);

        // send the request to the server.
        this.connection.send([Protocol.ROOM_LIST, requestId, roomName]);

        this.roomsAvailableRequests[requestId] = (roomsAvailable) => {
            removeRequest();
            clearTimeout(rejectionTimeout);
            callback(roomsAvailable);
        };
    }

    public close() {
        this.connection.close();
    }

    private connect(colyseusid: string) {
        this.id = colyseusid || '';

        this.connection = this.createConnection();

        this.connection.onMessage = function (data) {
            this.onMessageCallback(data);
        }

        this.connection.onClose = (e) => this.onClose.dispatch(e);
        this.connection.onError = (e) => this.onError.dispatch(e);

        // check for id on cookie
        this.connection.onopen = () => {
            if (this.id) {
                this.onOpen.dispatch();
            }
        };
    }

    private createConnection(path: string = '', options: any = {}) {
        // append colyseusid to connection string.
        var params: Array<String> = ["colyseusid=" + this.id];

        for (name in options) {
            params.push(name + "=" + options[name]);
        }

        return new Connection(this.hostname + "/" + path + "?" + params.join('&'));
    }

    /**
     * @override
     */
    private onMessageCallback(data: Bytes) {
        var message = MsgPack.decode(data);
        var code = message[0];

        if (code === Protocol.USER_ID) {
            setItem('colyseusid', message[1]);

            this.id = message[1];

            this.onOpen();

        } else if (code === Protocol.JOIN_ROOM) {
            var requestId = message[2];
            var room = this.connectingRooms[ requestId ];

            if (!room) {
                console.warn('colyseus.js: client left room before receiving session id.');
                return;
            }

            room.id = message[1];
            this.rooms.set(room.id, room);

            room.connect(this.createConnection(room.id, room.options));
            this.connectingRooms.remove(requestId);

        } else if (code === Protocol.JOIN_ERROR) {
            trace('colyseus.js: server error:' + message[2]);

            // general error
            this.onError(message[2]);

        } else if (code === Protocol.ROOM_LIST) {
            if (this.roomsAvailableRequests[message[1]]) {
                this.roomsAvailableRequests[message[1]](message[2]);

            } else {
                console.warn('receiving ROOM_LIST after timeout:', message[2]);
            }

        } else {
            this.onMessage.dispatch(message);
        }

    }

}
