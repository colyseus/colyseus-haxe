import { Schema, type, MapSchema, ArraySchema } from "@colyseus/schema";
import { Room } from "colyseus";

class Container extends Schema {
    @type({ map: "string" }) testMap = new MapSchema<string>();
    @type(["number"]) testArray = new ArraySchema<number>();
}

class State extends Schema {
    @type(Container) container = new Container();
}

export class MyRoom extends Room {
    state = new State();

    async onCreate(_: any) {
        let int: number = 0;

        this.clock.setInterval(() => {
            this.state.container.testMap.set(String(int % 3), String(int));
            this.state.container.testArray.push(int);

            int++;

            if (int % 10 == 0) {
                this.state.container.testMap = new MapSchema<string>();
                this.state.container.testArray = new ArraySchema<number>();
                console.log("RESET");
            }
        }, 1000);

    }

}
