package io.colyseus.state_listener;

import io.colyseus.state_listener.Compare;

typedef Listener = {
    callback: DataChange->Void,
    rules: List<EReg>,
    rawRules: Array<String>
}

typedef DataChange = {
    path: Dynamic,
    operation: String,
    value: Dynamic,
    ?rawPath: Array<String>
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
        ":*" => ~/^(.+)$/,
    ];

    public function new (state: Dynamic) {
        this.state = state;
        this.reset();
    }

    public function set (newState: Dynamic): Array<PatchObject> {
        var patches = Compare.getPatchList(this.state, newState);
        this.checkPatches(patches, this.listeners, this.defaultListener);
        this.state = newState;
        return patches;
    }

    public function registerPlaceholder (placeholder: String, matcher: EReg) {
        this.matcherPlaceholders[ placeholder ] = matcher;
    }

    public function listen (segments: Dynamic, ?callback: DataChange->Void, ?immediate: Bool): Listener {
        var rawRules: Array<String>;

        if (Reflect.isFunction(segments)) {
            rawRules = [];
            callback = segments;

        } else {
            rawRules = segments.split("/");
        }

        var listener: Listener = {
            callback: callback,
            rawRules: rawRules,
            rules: Lambda.map(rawRules, function(segment) {
                if (Std.is(segment, String)) {
                    // replace placeholder matchers
                    if (segment.indexOf(":") == 0) {
                        var matcher = this.matcherPlaceholders.get(segment);

                        if (matcher == null) {
                            matcher = this.matcherPlaceholders.get(":*");
                        }

                        return matcher;
                    } else {
                        return new EReg('^' + segment + '$', "m");
                    }
                } else {
                    return cast(segment, EReg);
                }
            })
        };

        if (rawRules.length == 0) {
            this.defaultListener = listener;

        } else {
            this.listeners.push(listener);
        }

        // immediatelly try to trigger this listener.
        if (immediate) {
            this.checkPatches(Compare.getPatchList({}, this.state), [listener]);
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
                if (listener == null) continue;

                var pathVariables = this.getPathVariables(patches[i], listener);
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
                this.defaultListener.callback({
                    path: patches[i].path,
                    operation: patches[i].operation,
                    value: patches[i].value
                });
            }
        }
    }

    private function getPathVariables (patch: PatchObject, listener: Listener): Dynamic {
        // skip if rules count differ from patch
        if (patch.path.length != listener.rules.length) {
            return null;
        }

        var i = 0;
        var path: Dynamic = {};

        for (rule in listener.rules) {
            var matches = this.getMatches(rule, patch.path[i]);

            if (matches.length == 0 || matches.length > 2) {
                return null;

            } else if (listener.rawRules[i].substr(0, 1) == ":") {
                Reflect.setProperty(path, listener.rawRules[i].substr(1), matches[0]);
            }
            i++;
        }

        return path;
    }

    private function getMatches(ereg:EReg, input:String, index:Int = 0):Array<String> {
        var matches = [];

        while (ereg.match(input)) {
            matches.push(ereg.matched(index));
            input = ereg.matchedRight();
        }

        return matches;
    }


    private function reset () {
        this.listeners = [];
    }

}
