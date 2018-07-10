package io.colyseus.state_listener;

export interface PatchObject {
    path: string[];
    operation: "add" | "remove" | "replace";
    value?: any;
}

export function compare(tree1: any, tree2: any): any[] {
    let patches: PatchObject[] = [];
    generate(tree1, tree2, patches, []);
    return patches;
}

function concat(arr: string[], value: string) {
    let newArr = arr.slice();
    newArr.push(value);
    return newArr;
}

function objectKeys (obj: any) {
    if (Array.isArray(obj)) {
        let keys = new Array(obj.length);

        for (let k = 0; k < keys.length; k++) {
            keys[k] = "" + k;
        }

        return keys;
    }

    if (Object.keys) {
        return Object.keys(obj);
    }

    let keys = [];
    for (let i in obj) {
        if (obj.hasOwnProperty(i)) {
            keys.push(i);
        }
    }
    return keys;
};

// Dirty check if obj is different from mirror, generate patches and update mirror
function generate(mirror: any, obj: any, patches: PatchObject[], path: string[]) {
    let newKeys = objectKeys(obj);
    let oldKeys = objectKeys(mirror);
    let changed = false;
    let deleted = false;

    for (let t = oldKeys.length - 1; t >= 0; t--) {
        let key = oldKeys[t];
        let oldVal = mirror[key];
        if (obj.hasOwnProperty(key) && !(obj[key] === undefined && oldVal !== undefined && Array.isArray(obj) === false)) {
            let newVal = obj[key];
            if (typeof oldVal == "object" && oldVal != null && typeof newVal == "object" && newVal != null) {
                generate(oldVal, newVal, patches, concat(path, key));
            }
            else {
                if (oldVal !== newVal) {
                    changed = true;
                    patches.push({operation: "replace", path: concat(path, key), value: newVal});
                }
            }
        }
        else {
            patches.push({operation: "remove", path: concat(path, key)});
            deleted = true; // property has been deleted
        }
    }

    if (!deleted && newKeys.length == oldKeys.length) {
        return;
    }

    for (let t = newKeys.length - 1; t >= 0; t--) {
        let key = newKeys[t];
        if (!mirror.hasOwnProperty(key) && obj[key] !== undefined) {
            let newVal = obj[key];
            let addPath = concat(path, key);
            // compare deeper additions
            if (typeof newVal == "object" && newVal != null) {
                generate({}, newVal, patches, addPath);
            }
            patches.push({ operation: "add", path: addPath, value: newVal });
        }
    }
}
