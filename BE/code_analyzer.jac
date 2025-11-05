# Analyzer for source code files using LLM to extract structure and relationships.

import from byllm.llm { Model }
import os;
import re;
import json;

glob llm = Model(model_name="openai/gpt-4o-mini", verbose=False, timeout=120);

#Support Node Types
node File { has path: str; has lang: str = ""; }
node Module { has name: str; has path: str = ""; }
node Class { has name: str; has file: str = ""; }
node Function { has name: str; has file: str = ""; }

#Support Edge Types
edge Contains {}
edge Imports {}
edge Inherits {}
edge Calls {}

#Main Analyzer Node
node CodeAnalyzer {
    has repo_dir: str;
    has files: list[str] = [];
    has parsed_count: int = 0;

    def guess_lang(path: str) -> str {
    let lower = path.lower();

    if lower.endswith(".py") {
        return "python";
    } elif lower.endswith(".jac") {
        return "jac";
    } elif lower.endswith(".php") {
        return "php";
    } elif lower.endswith(".js") or lower.endswith(".jsx") {
        return "javascript";
    } elif lower.endswith(".ts") or lower.endswith(".tsx") {
        return "typescript";
    } elif lower.endswith(".java") {
        return "java";
    } elif lower.endswith(".c") {
        return "c";
    } elif lower.endswith(".cpp") or lower.endswith(".cc") or lower.endswith(".cxx") {
        return "cpp";
    } elif lower.endswith(".cs") {
        return "csharp";
    } elif lower.endswith(".go") {
        return "go";
    } elif lower.endswith(".rs") {
        return "rust";
    } elif lower.endswith(".rb") {
        return "ruby";
    } elif lower.endswith(".swift") {
        return "swift";
    } elif lower.endswith(".kt") or lower.endswith(".kts") {
        return "kotlin";
    } elif lower.endswith(".r") {
        return "r";
    } elif lower.endswith(".scala") {
        return "scala";
    } elif lower.endswith(".pl") or lower.endswith(".pm") {
        return "perl";
    } elif lower.endswith(".sh") or lower.endswith(".bash") {
        return "shell";
    } elif lower.endswith(".html") or lower.endswith(".htm") {
        return "html";
    } elif lower.endswith(".css") {
        return "css";
    } else {
        return "other";
    }
}

    def build_ccg_llm(path: str, content: str, lang: str) -> dict[str, str] by llm(method="Simple");

    

    def graph_view() -> str {
    classes = [root --> (`?Class)];
    funcs = [root --> (`?Function)];
    let summary = "Classes Detected:\n";
    for c in classes {
        summary += "- " + c.name + " (" + c.file + ")\n";
    }
    summary += "\nFunctions Detected:\n";
    for f in funcs {
        summary += "- " + f.name + " (" + f.file + ")\n";
    }
    return summary;
}


    def attach_ccg(ccg: dict) {
        if not ccg or "file" not in ccg { 
            return; 
        }

        fnode = File(path=ccg["file"], lang=self.guess_lang(ccg["file"]));
        self ++> fnode;

        if "classes" in ccg {
            for c in ccg["classes"] {
                cname = "";
                bases = [];

                if type(c) == dict {
                    cname = c.get("name", "");
                    if "bases" in c {
                        bases = c["bases"];
                    }
                } else {
                    cname = str(c);
                }

                if not cname { continue; }

                cnode = Class(name=cname, file=ccg["file"]);
                self ++> cnode;

                for b in bases {
                    bnode = Class(name=str(b), file="");
                    bnode +>:Inherits:+> cnode;
                }
            }
        }

        if "functions" in ccg {
            for fn in ccg["functions"] {
                fname = fn["name"] if type(fn) == dict and "name" in fn else str(fn);
                if not fname { continue; }

                fndef = Function(name=fname, file=ccg["file"]);
                fnode +>:Contains:+> fndef;
            }
        }

        if "calls" in ccg {
            for call in ccg["calls"] {
                if type(call) != dict or "from" not in call or "to" not in call { continue; }

                src = [root --> (`?Function)](?name == call["from"]);
                dst = [root --> (`?Function)](?name == call["to"]);
                if src and dst {
                    src[0] +>:Calls:+> dst[0];
                }
            }
    
        }

        if "nodes" in ccg {
    for n in ccg["nodes"] {
        let nname = n["name"] if type(n) == dict and "name" in n else str(n);
        if not nname { continue; }
        # Represent Jac node as a Class-like vertex (or define a new Node archetype)
        let cnode = Class(name=nname, file=ccg["file"]);
        self ++> cnode;
    }
}

if "walkers" in ccg {
    for w in ccg["walkers"] {
        let wname = w["name"] if type(w) == dict and "name" in w else str(w);
        if not wname { continue; }
        let fndef = Function(name=wname, file=ccg["file"]);
        fnode +>:Contains:+> fndef;
    }
}

if "edges" in ccg {
    for e in ccg["edges"] {
        let ename = e["name"] if type(e) == dict and "name" in e else str(e);
        if not ename { continue; }
        # store as Class-like too, or add a dedicated Edge node archetype if you prefer
        let enode = Class(name=ename, file=ccg["file"]);
        self ++> enode;
    }
}

    }
   can analyze with entry {
    if not self.files {
        print("No files to analyze.");
        disengage;
    }

    let total = len(self.files);
    print("Total files detected: " + str(total));
    if len(self.files) > 60 {
    llm = Model(model_name="openai/gpt-3.5-turbo", verbose=False, timeout=90);
}

    # --- Dynamic scan control ---
    if total <= 6 {
        print("Mode: Full analysis");
        self.run_analysis(self.files, "deep");
    } elif total <= 100 {
        print("Mode: Balanced sampling (20 representative files)");
        let sample = self.files[:8];
        self.run_analysis(sample, "balanced");
    } else {
        print("Mode: Quick summary scan (10 representative files)");
        let sample = self.files[:10];
        self.run_analysis(sample, "summary");
    }

    print("Parsed files: " + str(self.parsed_count));
}

def run_analysis(files: list, mode: str) {
    for p in files {
        let lang = self.guess_lang(p);
        let abs_path = os.path.join(self.repo_dir, p);

        if not os.path.exists(abs_path) {
            print("Skipping missing file: " + p);
            continue;
        }

        # --- Handle notebooks (.ipynb) ---
if p.endswith(".ipynb") {
    print("Notebook detected: " + p);

    let content = "";  # ensure declared for later use
    let raw = open(abs_path, "r", encoding="utf-8", errors="ignore").read();
    let raw_stripped = raw.lstrip();

    if not raw_stripped {
        print("Skipping empty or invalid notebook: " + p);
        continue;
    }

    if raw_stripped.startswith("{") or raw_stripped.startswith("[") {
        let nb_json = json.loads(raw_stripped);

        if "cells" in nb_json and len(nb_json["cells"]) > 0 {
            let src_cells = [];
            for cell in nb_json["cells"] {
                if cell.get("cell_type", "") == "code" and "source" in cell {
                    src_cells.append("\n".join(cell["source"]));
                }
                if len(src_cells) >= 2 { break; }
            }
            if len(src_cells) > 0 {
                content = "\n\n".join(src_cells)[:800];
                print("Extracted " + str(len(src_cells)) + " code cell(s) from notebook.");
            } else {
                print("No usable code in notebook: " + p);
                continue;
            }
        } else {
            print("No cells in notebook: " + p);
            continue;
        }
    } else {
        print("Notebook file not valid JSON, skipping: " + p);
        continue;
    }

    # From here on, 'content' contains up to 800 chars of code for LLM
} else { print("Processing regular file: " + p);
        let content = open(abs_path, "r", encoding="utf-8", errors="ignore").read()[:800];
    }
    # normal file path
   
        let supported_langs = [
            "python", "jac", "php", "javascript", "typescript", "java",
            "c", "cpp", "csharp", "go", "rust", "ruby", "swift", "kotlin",
            "r", "scala", "perl", "shell", "html", "css"
        ];

        if lang not in supported_langs {
            print("Skipping unsupported file: " + p + " (" + lang + ")");
            continue;
        }

        print("Analyzing [" + lang + "]: " + p);

        let result = self.build_ccg_llm(p, content, lang);

        if type(result) == dict {
            if "file" not in result { result["file"] = p; }
            self.attach_ccg(result);
            self.parsed_count += 1;
        } else {
            print("Fallback summary mode for: " + p);
            let fallback = self.build_ccg_llm_summary(p, content, lang);
            if type(fallback) == dict {
                if "file" not in fallback { fallback["file"] = p; }
                self.attach_ccg(fallback);
                self.parsed_count += 1;
            } else {
                print("Skipping file: " + p + " (no valid output)");
            }
        }
    }

}

}

sem CodeAnalyzer.build_ccg_llm = """
You are a **fast, lightweight code structure parser**.

TASK:
Read the provided {lang} source code and extract ONLY the first few *top-level* structural elements — up to:
- 2 classes
- 2 functions
- 2 node
- 2 walker
- 2 edge
Return STRICT JSON (no text or markdown).

SCHEMA:
{
  "file": "<path>",
  "classes": [{"name": "ClassName", "bases": ["BaseClass"]}],
  "functions": [{"name": "func_name", "args": ["arg1","arg2"], "calls": ["callee_func"]}],
  "nodes": [{"name": "NodeName"}],
  "walkers": [{"name": "WalkerName"}],
  "edges": [{"name": "EdgeName"}],
  "calls": [{"from": "caller", "to": "callee"}]
}

RULES:
1. Always include all keys, even if empty.
2. Only extract up to the limits above (skip the rest).
3. Output MUST be valid JSON — no explanations or markdown.
4. Names must match the code exactly (case-sensitive).
5. "calls" should list only direct call-site relationships by name.
6. If nothing is found, return the schema with empty lists.

LANGUAGE RULES:

[Python]
- Detect top-level class and def declarations.
- For each function/method, include args and calls if visible.
- Ignore imports and decorators.
- Stop after extracting 2 classes and 2 functions.

[JacLang]
- Detect node, walker, edge, and def declarations.
- Include at most 1 node, 1 walker, 1 edge, and 2 functions.
- Record direct calls between them ({"from":"caller","to":"callee"}).
- Stop scanning after these top-level items are found.

[Other languages]
- Detect only up to 2 visible top-level declarations (classes or functions).

EXAMPLES (abbreviated)

Python input:
class A: pass
def z(): pass

Jac input:
node N {}
walker W { can run with entry { greet(); } }
def greet() {}
""";


