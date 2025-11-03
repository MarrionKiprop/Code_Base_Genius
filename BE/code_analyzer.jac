# agents/code_analyzer.jac
import from byllm.llm { Model }
import os;
import re;

glob llm = Model(model_name="openai/gpt-4o-mini", verbose=False);

node File { has path: str; has lang: str = ""; }
node Module { has name: str; has path: str = ""; }
node Class { has name: str; has file: str = ""; }
node Function { has name: str; has file: str = ""; }

edge Contains {}
edge Imports {}
edge Inherits {}
edge Calls {}

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


    def build_ccg_llm(path: str, content: str, lang: str) -> dict[str, str] by llm(method="ReAct");

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
    }

    can analyze with entry {
        if not self.files {
            print("No files to analyze.");
            disengage;
        }

        for p in self.files {
    let lang = self.guess_lang(p);

    # --- Supported languages list ---
    let supported_langs = [
        "python",
        "jac",
        "php",
        "javascript",
        "typescript",
        "java",
        "c",
        "cpp",
        "csharp",
        "go",
        "rust",
        "ruby",
        "swift",
        "kotlin",
        "r",
        "scala",
        "perl",
        "shell",
        "html",
        "css"
    ];

    if lang not in supported_langs {
        print("Skipping unsupported file: " + p + " (" + lang + ")");
        continue;
    }

    let abs_path = os.path.join(self.repo_dir, p);
    if not os.path.exists(abs_path) {
        print("Failed to read " + abs_path);
        continue;
    }

    print("Analyzing [" + lang + "]: " + p);
    let content = open(abs_path, "r", encoding="utf-8").read();
    let result = self.build_ccg_llm(p, content, lang);

    if type(result) != dict {
        print("Skipping unstructured LLM output for: " + p);
        continue;
    }

    if "file" not in result {
        result["file"] = p;
    }

    self.attach_ccg(result);
    self.parsed_count += 1;
}

print("Parsed files: " + str(self.parsed_count));
    }
}
sem CodeAnalyzer.build_ccg_llm = """
Analyze the following source code from a file written in {lang}.
Extract all of these structures and return them strictly as a JSON object.

For Python (.py):
- Detect all class definitions, including their base classes (if any).
- Detect all function definitions with their names and argument lists.
- Detect any function calls (who calls who).

For Jac (.jac):
- Detect all `node`, `edge`, and `walker` definitions.
- Include any `can ... with entry` walker entry points.
- Detect walker-to-walker or walker-to-node calls (`->`, `++>`, `<++`).

Return a JSON object of this form:
{
  "file": "<path>",
  "classes": [{"name": "ClassName", "bases": ["Base1", "Base2"]}],
  "nodes": [{"name": "NodeName"}],
  "walkers": [{"name": "WalkerName"}],
  "edges": [{"name": "EdgeName"}],
  "functions": [{"name": "func_name", "args": ["a","b"]}],
  "calls": [{"from": "caller", "to": "callee"}]
}

Rules:
- Do not include code text, comments, or explanations.
- Return **only valid JSON**, no markdown, no prose.
- If a category has no data, you may omit it or use an empty array.
- Keep output short, consistent, and properly quoted.
"""
;
