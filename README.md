<div align="center">
  <a href="https://github.com/colyseus/colyseus">
    <img src="https://github.com/colyseus/colyseus/blob/master/media/logo.svg?raw=true" width="40%" height="100" />
  </a>
  <br>
  <br>
  <a href="https://npmjs.com/package/colyseus">
    <img src="https://img.shields.io/npm/dm/colyseus.svg?style=for-the-badge&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAQAAAC1+jfqAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAAmJLR0QAAKqNIzIAAAAJcEhZcwAADsQAAA7EAZUrDhsAAAAHdElNRQfjAgETESWYxR33AAAAtElEQVQoz4WQMQrCQBRE38Z0QoTcwF4Qg1h4BO0sxGOk80iCtViksrIQRRBTewWxMI1mbELYjYu+4rPMDPtn12ChMT3gavb4US5Jym0tcBIta3oDHv4Gwmr7nC4QAxBrCdzM2q6XqUnm9m9r59h7Rc0n2pFv24k4ttGMUXW+sGELTJjSr7QDKuqLS6UKFChVWWuFkZw9Z2AAvAirKT+JTlppIRnd6XgaP4goefI2Shj++OnjB3tBmHYK8z9zAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDE5LTAyLTAxVDE4OjE3OjM3KzAxOjAwGQQixQAAACV0RVh0ZGF0ZTptb2RpZnkAMjAxOS0wMi0wMVQxODoxNzozNyswMTowMGhZmnkAAAAZdEVYdFNvZnR3YXJlAHd3dy5pbmtzY2FwZS5vcmeb7jwaAAAAAElFTkSuQmCC">
  </a>
  <a href="https://discord.gg/RY8rRS7">
    <img src="https://img.shields.io/discord/525739117951320081.svg?style=for-the-badge&colorB=7581dc&logo=discord&logoColor=white">
  </a>
  <h3>
     Multiplayer Game Client for <a href="https://haxe.org/">Haxe</a> <br /><a href="https://docs.colyseus.io/getting-started/haxe">View documentation</a>
  </h3>
</div>

## Running the demo project

First, download and install [Haxe](https://haxe.org/download/).

The [`example`](https://github.com/colyseus/colyseus-haxe/blob/master/example/openfl) project can be compiled to `html5`, `neko`, `cpp`, `ios`, etc.

### Compiling the demo project to `html5`

```
git clone https://github.com/colyseus/colyseus-haxe.git
cd colyseus-haxe/example/openfl
haxelib install openfl
haxelib install lime
haxelib install tink_http
haxelib install tink_await
haxelib install swf
haxelib install colyseus-websocket
haxelib run lime test project.xml html5
```

### Running the server

The demo project uses the **SDK Test Server**. You can start the server by running the following commands:

```
git clone https://github.com/colyseus/sdks-test-server
cd sdks-test-server
npm install
npm start
```

## Development

Running the test-suite:

```
haxe hxml/test.js.hxml
```

## Troubleshooting

> Error#500: Chunked encoding is not supported and the content-length header is required.

Make sure your HTTP responses from the server-side don't respond with `Transfer-Encoding: chunked` header. Include the `Content-Length: xxx` header to avoid _"chunked"_ responses.

## Dependencies

[colyseus-haxe](https://github.com/colyseus/colyseus-haxe) depends on [`colyseus-websocket`](https://github.com/colyseus/colyseus-websocket-hx)

## License

MIT
