package io.colyseus.state_listener;

interface Listener {
    public var callback: Function;
    public var rules: Array<RegExp>;
    public var rawRules: Array<String>;
}

interface DataChange extends PatchObject {
    public var path: Dynamic;
    public var rawPath: Array<String>;
}

class StateContainer {
    public var state: Dynamic;
    private var listeners: Array<Listener>[] = [];
    private var defaultListener: Listener;

    private var matcherPlaceholders: {[id: string]: RegExp} = {
        ":id": /^([a-zA-Z0-9\-_]+)$/,
        ":number": /^([0-9]+)$/,
        ":string": /^(\w+)$/,
        ":axis": /^([xyz])$/,
        ":*": /(.*)/,
    }

    public function new (state: Dynamic) {
        this.state = state;
        this.reset();
    }

    public function set (newState: T): PatchObject[] {
        var patches = compare(this.state, newState);
        this.checkPatches(patches, this.listeners, this.defaultListener);
        this.state = newState;
        return patches;
    }

    public function registerPlaceholder (placeholder: string, matcher: RegExp) {
        this.matcherPlaceholders[ placeholder ] = matcher;
    }

    public function listen (segments: string | Function, callback?: Function, immediate?: boolean): Listener {
        var rules: string[];

        if (typeof(segments)==="function") {
            rules = [];
            callback = segments;

        } else {
            rules = segments.split("/");
        }

        if (callback.length > 1) {
            console.warn(".listen() accepts only one parameter.");
        }

        var listener: Listener = {
            callback: callback,
            rawRules: rules,
            rules: rules.map(segment => {
                if (typeof(segment)==="string") {
                    // replace placeholder matchers
                    return (segment.indexOf(":") === 0)
                        ? this.matcherPlaceholders[segment] || this.matcherPlaceholders[":*"]
                        : new RegExp(`^${ segment }$`);
                } else {
                    return segment;
                }
            })
        };

        if (rules.length === 0) {
            this.defaultListener = listener;

        } else {
            this.listeners.push(listener);
        }

        // immediatelly try to trigger this listener.
        if (immediate) {
            this.checkPatches(compare({}, this.state), [listener]);
        }

        return listener;
    }

    public function removeListener (listener: Listener) {
        for (var i = this.listeners.length-1; i >= 0; i--) {
            if (this.listeners[i] === listener) {
                this.listeners.splice(i, 1);
            }
        }
    }

    public function removeAllListeners () {
        this.reset();
    }

    private function checkPatches(patches: (PatchObject & { matched: boolean })[], listeners: Listener[], defaultListener?: Listener) {
        for (var j = 0, len = listeners.length; j < len; j++) {
            var listener = listeners[j];

            for (var i = patches.length - 1; i >= 0; i--) {
                var pathVariables = listener && this.getPathVariables(patches[i], listener);

                if (pathVariables) {
                    listener.callback({
                        path: pathVariables,
                        rawPath: patches[i].path,
                        operation: patches[i].operation,
                        value: patches[i].value
                    });

                    patches[i].matched = true;
                }
            }
        }

        // trigger default listener callback with each unmatched patch
        if (defaultListener) {
            for (var i = patches.length - 1; i >= 0; i--) {
                if (!patches[i].matched) {
                    defaultListener.callback(patches[i]);
                }
            }
        }
    }

    private function getPathVariables (patch: PatchObject, listener: Listener): any {
        // skip if rules count differ from patch
        if (patch.path.length !== listener.rules.length) {
            return false;
        }

        var path: any = {};

        for (var i = 0, len = listener.rules.length; i < len; i++) {
            var matches = patch.path[i].match(listener.rules[i]);

            if (!matches || matches.length === 0 || matches.length > 2) {
                return false;

            } else if (listener.rawRules[i].substr(0, 1) === ":") {
                path[ listener.rawRules[i].substr(1) ] = matches[1];
            }
        }

        return path;
    }

    private function reset () {
        this.listeners = [];
    }

}
