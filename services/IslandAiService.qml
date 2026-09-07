pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Island AI answers for the "." prefix.
 *
 * Same pattern as TranslateService: watches LauncherSearch.query itself so
 * LauncherSearch.results stays a pure binding with no side effects.
 * Single-shot, no tools, no history — the full sidebar chat stays in Ai.qml.
 * Answer shows inline in the island results card.
 */
Singleton {
    id: root

    readonly property string prefix: Config.options.search.prefix.ai ?? "."
    readonly property bool active: LauncherSearch.query.startsWith(root.prefix)
    readonly property string rawText: root.active ? LauncherSearch.query.slice(root.prefix.length) : ""
    readonly property string text: root.rawText.trim()

    property string result: ""
    // "idle" | "loading" | "ok" | "failed" | "nokey"
    property string status: "idle"

    readonly property var model: Ai.models[Ai.currentModelId]
    readonly property string modelName: (root.model && root.model.name) ? root.model.name : "AI"

    onTextChanged: {
        root.result = "";
        if (!root.active || root.text.length === 0) {
            root.status = "idle";
            debounce.stop();
            aiProc.running = false;
            return;
        }
        if (!root.model) {
            root.status = "failed";
            return;
        }
        if (root.model.requires_key && ((Ai.apiKeys[root.model.key_id] ?? "").length === 0)) {
            root.status = "nokey";
            return;
        }
        root.status = "loading";
        debounce.restart();
    }

    // Re-evaluate key availability when the keyring loads/changes.
    Connections {
        target: Ai
        function onApiKeysChanged() {
            if (root.active && root.text.length > 0 && root.status === "nokey" && root.model && !root.model.requires_key)
                return;
            if (root.active && root.text.length > 0 && root.status === "nokey") {
                if (root.model && root.model.requires_key && ((Ai.apiKeys[root.model.key_id] ?? "").length > 0)) {
                    root.status = "loading";
                    debounce.restart();
                }
            }
        }
    }

    Timer {
        id: debounce
        interval: 600
        repeat: false
        onTriggered: {
            aiProc.running = false;
            aiProc.buffer = "";
            const m = root.model;
            if (!m)
                return;
            aiProc.environment["ISLAND_AI_QUERY"] = root.text;
            aiProc.environment["ISLAND_AI_ENDPOINT"] = m.endpoint ?? "";
            aiProc.environment["ISLAND_AI_KEY"] = m.requires_key ? (Ai.apiKeys[m.key_id] ?? "") : "";
            aiProc.environment["ISLAND_AI_FORMAT"] = m.api_format ?? "openai";
            aiProc.environment["ISLAND_AI_MODEL"] = m.model ?? "";
            try {
                aiProc.environment["ISLAND_AI_HEADERS"] = JSON.stringify(m.extraHeaders ?? {});
            } catch (e) {
                aiProc.environment["ISLAND_AI_HEADERS"] = "{}";
            }
            try {
                aiProc.environment["ISLAND_AI_PARAMS"] = JSON.stringify(m.extraParams ?? {});
            } catch (e) {
                aiProc.environment["ISLAND_AI_PARAMS"] = "{}";
            }
            aiProc.running = true;
        }
    }

    Process {
        id: aiProc
        property string buffer: ""
        command: ["python3", "-c", root.script]

        readonly property string script: [
            "import os,sys,json,urllib.request",
            "q=os.environ.get('ISLAND_AI_QUERY','').strip()",
            "endpoint=os.environ.get('ISLAND_AI_ENDPOINT','')",
            "key=os.environ.get('ISLAND_AI_KEY','')",
            "fmt=os.environ.get('ISLAND_AI_FORMAT','openai')",
            "model=os.environ.get('ISLAND_AI_MODEL','')",
            "try:\n    extra_h=json.loads(os.environ.get('ISLAND_AI_HEADERS','{}') or '{}')\nexcept:\n    extra_h={}",
            "try:\n    extra_p=json.loads(os.environ.get('ISLAND_AI_PARAMS','{}') or '{}')\nexcept:\n    extra_p={}",
            "sys_prompt='You are a helpful assistant inside a Linux desktop search bar. Answer briefly in 1-4 sentences unless asked otherwise. Plain text, no markdown headers.'",
            "def out(t):\n    sys.stdout.write(t)",
            "try:",
            "    req=None",
            "    if fmt=='gemini':",
            "        url=endpoint+('' if ('?key=' in endpoint or '&key=' in endpoint) else ('?key='+key))",
            "        body={'contents':[{'role':'user','parts':[{'text':q}]}],'system_instruction':{'parts':[{'text':sys_prompt}]},'generationConfig':{'temperature':0.5}}",
            "        data=json.dumps(body).encode()",
            "        headers={'Content-Type':'application/json'}",
            "        req=urllib.request.Request(url,data=data,headers=headers,method='POST')",
            "    else:",
            "        body={'model':model,'messages':[{'role':'system','content':sys_prompt},{'role':'user','content':q}],'temperature':0.5,'stream':False}",
            "        try:\n            body.update(extra_p if isinstance(extra_p,dict) else {})\n        except:\n            pass",
            "        headers={'Content-Type':'application/json'}",
            "        if key:\n            headers['Authorization']='Bearer '+key",
            "        try:\n            [headers.__setitem__(k,v) for k,v in extra_h.items()]\n        except:\n            pass",
            "        req=urllib.request.Request(endpoint,data=json.dumps(body).encode(),headers=headers,method='POST')",
            "    r=urllib.request.urlopen(req,timeout=30)",
            "    j=json.loads(r.read().decode('utf-8','replace'))",
            "    ans=''",
            "    if fmt=='gemini':",
            "        try:\n            parts=j.get('candidates',[{}])[0].get('content',{}).get('parts',[])\n            ans=''.join([p.get('text','') for p in parts]).strip()\n        except Exception as e:\n            ans=''",
            "        err=j.get('error')",
            "        ok=(r.status==200 and len(ans)>0)",
            "    else:",
            "        try:\n            ans=(j.get('choices',[{}])[0].get('message',{}).get('content','') or '').strip()\n        except:\n            ans=''",
            "        err=j.get('error')",
            "        ok=(r.status==200 and len(ans)>0)",
            "    is_err=isinstance(err,dict)",
            "    is_err_str=isinstance(err,str)",
            "    if is_err:\n        out('ERR: '+(err.get('message') or json.dumps(err))[:400])",
            "    elif is_err_str and len(err)>0:\n        out('ERR: '+err[:400])",
            "    elif ok:\n        out(ans[:2000])",
            "    else:\n        out('ERR: empty response')",
            "except Exception as e:",
            "    out('ERR: '+str(e)[:400])"
        ].join("\n")

        stdout: SplitParser {
            onRead: data => {
                aiProc.buffer += data + "\n";
            }
        }

        onExited: exitCode => {
            const output = aiProc.buffer.trim();
            if (output.startsWith("ERR:")) {
                root.result = output.slice(4).trim();
                root.status = "failed";
                return;
            }
            if (output.length === 0) {
                root.result = "";
                root.status = "failed";
                return;
            }
            root.result = output;
            root.status = "ok";
        }
    }
}
