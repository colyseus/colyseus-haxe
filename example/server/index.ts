import express from 'express';
import serveIndex from 'serve-index';
import path from 'path';
import cors from 'cors';
import { createServer } from 'http';
import { Server, LobbyRoom, RelayRoom } from 'colyseus';
import { monitor } from '@colyseus/monitor';

// Import demo room handlers
import { TestRoom } from './rooms/TestRoom';

const port = 2567;
const app = express();

app.use(cors());

// Attach WebSocket Server on HTTP Server.
const gameServer = new Server({
  server: createServer(app),
});

gameServer.define("test", TestRoom);

// (optional) attach web monitoring panel
app.use('/colyseus', monitor());

gameServer.onShutdown(function(){
  console.log(`game server is going down.`);
});

gameServer.listen(port);

console.log(`Listening on http://localhost:${ port }`);
