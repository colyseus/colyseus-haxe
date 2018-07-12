package io.colyseus.state_listener;

interface Listener {
    public var callback: Dynamic; // Function
    public var rules: List<EReg>;
    public var rawRules: List<String>;
}

interface PatchObject {
    public var path: Dynamic; // Array<String>
    public var operation: String;// "add" | "remove" | "replace";
    public var value: Dynamic;
}

interface DataChange extends PatchObject {
    public var rawPath: List<String>;
}

class StateContainer {
    public var state: Dynamic;
    private var listeners: Array<Listener> = [];
    private var defaultListener: Listener;

    private var matcherPlaceholders: Map<String, EReg> = [
        ":id" => ~/^([a-zA-Z0-9\-_]+)$/,
        ":number" => ~/^([0-9]+)$/,
        ":string" => ~/^(\w+)$/,
        ":axis" => ~/^([xyz])$/,
        ":*" => ~/(.*)/,
    ];

    public function new (state: Dynamic) {
        this.state = state;
        this.reset();
    }

    public function set (newState: Dynamic): Array<PatchObject> {
        var patches = Compare.compare(this.state, newState);
        this.checkPatches(patches, this.listeners, this.defaultListener);
        this.state = newState;
        return patches;
    }

    public function registerPlaceholder (placeholder: String, matcher: EReg) {
        this.matcherPlaceholders[ placeholder ] = matcher;
    }

    public function listen (segments: Dynamic/*String | Function*/, ?callback: DataChange->Void, ?immediate: Bool): Listener {
        var rules: Array<String>;


        if (Reflect.isFunction(segments)) {
            rules = [];
            callback = segments;

        } else {
            rules = segments.split("/");
        }

        var listener: Listener = {
            callback: callback,
            rawRules: rules,
            rules: Lambda.map(rules, function(segment) {
                if (Std.is(segment, String)) {
                    // replace placeholder matchers
                    if (segment.indexOf(":") == 0) {
                        var matcher = this.matcherPlaceholders.get(segment);
                        if (matcher == null) {
                            matcher = this.matcherPlaceholders.get(":*");
                        }
                        return matcher;
                    } else {
                        return new EReg("^" + segment + "$", "");
                    }
                } else {
                    return cast(segment, EReg);
                }
            })
        };

        if (rules.length == 0) {
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
        var i = this.listeners.length;
        while (--i >= 0) {
            if (this.listeners[i] == listener) {
                this.listeners.splice(i, 1);
            }
        }
    }

    public function removeAllListeners () {
        this.reset();
    }

    private function checkPatches(patches: Array<PatchObject>, listeners: Array<Listener>, ?defaultListener: Listener) {
        var i = patches.length;

        while (--i >= 0) {
            var matched = false;

            for (listener in listeners) {
                var pathVariables = listener && this.getPathVariables(patches[i], listener);
                if (pathVariables != null) {
                    listener.callback({
                        path: pathVariables,
                        rawPath: patches[i].path,
                        operation: patches[i].operation,
                        value: patches[i].value
                    });
                    matched = true;
                }
            }

            // check for fallback listener
            if (!matched && defaultListener != null) {
                this.defaultListener.callback(patches[i]);
            }
        }
    }

    private function getPathVariables (patch: PatchObject, listener: Listener): Dynamic {
        // skip if rules count differ from patch
        if (patch.path.length != listener.rules.length) {
            return false;
        }

        var path: Dynamic = {};

        for (i in 0..listener.rules.length) {
            var matches = patch.path[i].match(listener.rules[i]);

            if (!matches || matches.length == 0 || matches.length > 2) {
                return false;

            } else if (listener.rawRules[i].substr(0, 1) == ":") {
                path[ listener.rawRules[i].substr(1) ] = matches[1];
            }
        }

        return path;
    }

    private function reset () {
        this.listeners = [];
    }

}
