import config from "@colyseus/tools";

import { WebSocketTransport } from "@colyseus/ws-transport";
import { monitor } from "@colyseus/monitor";

import { RedisDriver } from "@colyseus/redis-driver";
import { RedisPresence } from "@colyseus/redis-presence";

import { auth } from "@colyseus/auth";
import { playground } from "@colyseus/playground";

/**
 * Import your Room files
 */
import { MyRoom } from "./rooms/MyRoom";
import "./config/auth";

export default config({
    options: {
        devMode: true,
        driver: new RedisDriver(),
        presence: new RedisPresence(),
    },

    initializeTransport: (options) => new WebSocketTransport(options),

    initializeGameServer: (gameServer) => {
        /**
         * Define your room handlers:
         */
        gameServer.define('my_room', MyRoom);

    },

    initializeExpress: (app) => {
        /**
         * Bind your custom express routes here:
         */
        app.get("/", (req, res) => {
            res.send(`Instance ID => ${process.env.NODE_APP_INSTANCE ?? "NONE"}`);
        });

        /**
         * Bind @colyseus/monitor
         * It is recommended to protect this route with a password.
         * Read more: https://docs.colyseus.io/tools/monitor/
         */
        app.use("/colyseus", monitor());

        // (optional) auth module
        app.use(auth.prefix, auth.routes());

        // (optional) playground
        app.use("/playground", playground());
    },


    beforeListen: () => {
        /**
         * Before before gameServer.listen() is called.
         */
    }
});
