import { Schema, type, MapSchema, ArraySchema } from "@colyseus/schema";
import { Room } from "colyseus";

class State extends Schema {
    @type({ map: "string" }) testMap = new MapSchema<string>();
    @type(["number"]) testArray = new ArraySchema<number>();
}

export class TestRoom extends Room {

    async onCreate(options) {
        this.setState(new State());

        let int: number = 0;

        this.clock.setInterval(() => {
            this.state.testMap.set(String(int % 3), String(int));
            this.state.testArray.push(int);

            int++;

            if (int % 10 == 0) {
                this.state.testMap = new MapSchema<string>();
                this.state.testArray = new ArraySchema<number>();
                console.log("RESET");
            }
        }, 1000);

    }

}
